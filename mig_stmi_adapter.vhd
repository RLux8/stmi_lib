----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 07/20/2025 02:04:12 PM
-- Design Name: 
-- Module Name: mig_stmi_adapter - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

library stmi_lib;
use stmi_lib.stmi.all;


entity mig_stmi_adapter is
    PORT(
        -- fast memory uif clock
        ui_clk              : IN    std_logic;
        ui_clk_sync_rst     : IN    std_logic;

        stmi_req            : IN     stmi_req_T;
        stmi_ans            : OUT    stmi_ans_T;

        app_addr            : OUT   std_logic_vector(27 downto 0);
        app_cmd             : OUT   std_logic_vector(2 downto 0);
        app_en              : OUT   std_logic;
        app_rdy             : IN    std_logic;

        app_rd_data         : IN    std_logic_vector(255 downto 0);
        app_rd_data_end     : IN    std_logic;
        app_rd_data_valid   : IN    std_logic;

        app_wdf_rdy         : IN    std_logic;
        app_wdf_mask        : OUT   std_logic_vector(31 downto 0);
        app_wdf_data        : OUT   std_logic_vector(255 downto 0);
        app_wdf_end         : OUT   std_logic;
        app_wdf_wren        : OUT   std_logic;
        init_calib_complete : IN    std_logic;
        cpu_req             : IN    std_logic
    );
end mig_stmi_adapter;

architecture behav of mig_stmi_adapter is
    type fast_if_state_T is (idle, READING, WRITING, STARTUP, CLEARING, ACK, WAITS);
    signal fast_if_state: fast_if_state_T;
    signal next_fast_if_state: fast_if_state_T;

    -- how many cycles init_calib_complete has to be active before starting to clear memory
    constant INITIAL_WAIT: positive := 1_000;

    type clearing_pattern_T is (ZEROES, CONST, ADDR);
    constant clearing_pattern: clearing_pattern_T := ADDR;
    constant INITIAL_CLEAR: boolean := false;

    signal clear_counter: std_logic_vector(app_addr'range);

    signal stmi_res_n: std_logic;

    subtype UI_CMD_T is std_logic_vector(2 downto 0);
    constant WR_CMD: UI_CMD_T := "000";
    constant RD_CMD: UI_CMD_T := "001";

    signal burst_end_address: stmi_addr_T;
    signal burst_current_address: stmi_addr_T;

    signal handled_words: natural range 2 ** B_CNT_W downto 0;

    signal fast_active: boolean;
begin
    stmi_res_n <= not ui_clk_sync_rst;

    -- registers 
    mig_if_state_p: process (ui_clk, stmi_res_n) is
    begin
        if stmi_res_n = '0' then
            fast_if_state <= STARTUP;
            clear_counter <= (others => '0');
            fast_active <= false;
            burst_end_address <= (others => '0');
            burst_current_address <= (others => '0');
            handled_words <= 1;
        else
            if ui_clk'event and ui_clk = '1' then   
                case fast_if_state is
                    when STARTUP => 
                        if init_calib_complete = '1' and app_rdy = '1' then
                            if to_integer(unsigned(clear_counter)) /= INITIAL_WAIT then
                                clear_counter <= std_logic_vector(unsigned(clear_counter) + 1);
                            else
                                if INITIAL_CLEAR then
                                    fast_if_state <= CLEARING;
                                else
                                    fast_if_state <= idle;
                                end if;
                                clear_counter <= (others => '0');
                            end if;
                        end if;

                    when CLEARING =>
                        if app_rdy = '1' and app_wdf_rdy = '1' then
                            clear_counter <= std_logic_vector(unsigned(clear_counter) + 8);
                        end if;

                        if clear_counter = 28X"8000000" then
                            fast_if_state <= idle;
                        end if;

                    when idle =>
                        if stmi_req.req and fast_active then  
                            if stmi_req.mode = WR_MODE then
                                fast_if_state <= WRITING;

                                if app_rdy = '1' then
                                    burst_current_address <= std_logic_vector(unsigned(stmi_req.addr) + 32);

                                    if app_wdf_rdy = '1' then
                                        if to_integer(unsigned(stmi_req.burstcnt)) = 1 then
                                            fast_if_state <= ACK;
                                        end if;
                                        
                                        handled_words <= 1;
                                    else
                                        handled_words <= 0;
                                    end if;
                                else
                                    burst_current_address <= stmi_req.addr;
                                end if;
                            else
                                if app_rdy = '1' then
                                    burst_current_address <= std_logic_vector(unsigned(stmi_req.addr) + 32);
                                else
                                    burst_current_address <= stmi_req.addr;
                                end if; 

                                fast_if_state <= READING;
                                handled_words <= 1;
                                burst_end_address(burst_end_address'high downto 5) <= std_logic_vector(unsigned(stmi_req.addr(burst_end_address'high downto 5)) + unsigned(stmi_req.burstcnt));
                            end if;
                        end if;

                    when READING => 
                        if app_rd_data_valid = '1' and handled_words = to_integer(unsigned(stmi_req.burstcnt)) then
                            fast_if_state <= WAITS;
                        end if;

                        if app_rdy = '1' and burst_current_address /= burst_end_address then
                            burst_current_address <= std_logic_vector(unsigned(burst_current_address) + 32);
                        end if;

                        if app_rd_data_valid = '1' then
                            handled_words <= handled_words + 1;
                        end if;

                    when WRITING => 
                        if app_wdf_rdy = '1' and handled_words = to_integer(unsigned(stmi_req.burstcnt)) then
                            fast_if_state <= WAITS;
                        end if;

                        if app_rdy = '1' and burst_current_address /= burst_end_address then
                            burst_current_address <= std_logic_vector(unsigned(burst_current_address) + 32);
                        end if;

                        if app_wdf_rdy = '1' and stmi_req.req then
                            handled_words <= handled_words + 1;
                        end if;
                    
                    when ACK =>
                         fast_if_state <= WAITS;
                         
                    when WAITS => 
                        fast_if_state <= idle;
                    
                end case;           

                fast_active <= true;
            end if;
        end if;
    end process mig_if_state_p;

   
    

    mig_if_output_p: process(all) is
        variable output_req: boolean;
    begin
        stmi_ans.ack            <= false;
        stmi_ans.done           <= false;
        stmi_ans.rdata          <= app_rd_data;

        app_addr                <= (others => '0');
        app_addr(26 downto 3)   <= stmi_req.addr(28 downto 5);
        app_cmd                 <= RD_CMD;
        app_en                  <= '0';

        app_wdf_end             <= '0'; 
        app_wdf_wren            <= '0';    
        app_wdf_end             <= '0';
        app_wdf_data            <= stmi_req.wdata;
        app_wdf_mask            <= (others => '0');
        

        -- for i in stmi_req.be'range loop
        --     app_wdf_mask(i) <= not stmi_req.be(i);
        -- end loop;

        case fast_if_state is
            when STARTUP => 
                app_addr        <= (others => '0');
                app_wdf_mask    <= (others => '0');

            when CLEARING => 
                if clear_counter /= 28X"8000000" then
                    case clearing_pattern is
                        when ZEROES => 
                            app_wdf_data    <= (others => '0');
                        when CONST => 
                            app_wdf_data    <= X"1234567812345678123456781234567812345678123456781234567812345678";
                        when ADDR => 
                            app_wdf_data    <= "0000" & clear_counter & "0000" & clear_counter & "0000" & clear_counter & "0000" & clear_counter
                                            & "0000" & clear_counter & "0000" & clear_counter & "0000" & clear_counter & "0000" & clear_counter;
                    end case;
                    
                    app_wdf_mask    <= (others => '0');
                    if app_rdy = '1' then
                        app_en <= '1';
                    end if;

                    if app_wdf_rdy = '1' then 
                        app_wdf_wren <= '1';
                        app_wdf_end  <= '1';
                    end if;
                    app_cmd <= WR_CMD;
                    app_addr <= clear_counter;
                end if;

            when idle => 
                if stmi_req.req and fast_active and init_calib_complete = '1' then 
                    app_en <= '1';
                    if stmi_req.mode = WR_MODE then
                        app_cmd <= WR_CMD;
                        if app_wdf_rdy = '1' and app_rdy = '1' then
                            app_wdf_wren <= '1';
                            app_wdf_end  <= '1' when to_integer(unsigned(stmi_req.burstcnt)) = 1 else
                                            '0';
                        end if;
                    else
                        app_cmd <= RD_CMD;
                    end if;
                end if;

            when WRITING => 
                stmi_ans.ack <= app_wdf_rdy = '1';
                stmi_ans.done <= app_wdf_rdy = '1' and handled_words = to_integer(unsigned(stmi_req.burstcnt));

                app_cmd <= WR_CMD;
                app_en <= '1' when burst_current_address /= burst_end_address else 
                          '0';

                app_wdf_wren <= '1' when stmi_req.req else
                                '0';
                app_wdf_end  <= '1' when stmi_req.req and handled_words = to_integer(unsigned(stmi_req.burstcnt)) else
                                '0';

                app_addr(26 downto 3)       <= burst_current_address(28 downto 5);

            when READING => 
                stmi_ans.ack <= app_rd_data_valid = '1';
                stmi_ans.done <= app_rd_data_valid = '1' and handled_words = to_integer(unsigned(stmi_req.burstcnt));

                app_cmd <= RD_CMD;
                app_en <= '1' when burst_current_address /= burst_end_address else 
                          '0';

                app_addr(26 downto 3)       <= burst_current_address(28 downto 5);

            when ACK => 
                stmi_ans.ack <= true;
                stmi_ans.done <= true;
                
            when WAITS => 
                null;
        end case;

    end process mig_if_output_p;


    --    imigif_ila : ila_1
    --    PORT MAP(
    --        clk => ui_clk,      
    --        probe0 => stmi_req.req,
    --        probe1 => stmi_ans.ack,
    --        probe2 => stmi_req.addr,
    --        probe3 => stmi_ans.rdata,
    --        probe4 => stmi_req.mode,
    --        probe5 => stmi_req.prio,
    --        probe6 => stmi_req.be,
    --        probe7 => app_addr,
    --        probe8 => app_cmd,
    --        probe9 => app_en,
    --        probe10 => app_rdy,
    --        probe11 => app_rdy,
    --        probe12 => app_rd_data,
    --        probe13 => app_rd_data_end,
    --        probe14 => app_rd_data_valid,
    --        probe15 => app_wdf_rdy,
    --        probe16 => app_wdf_mask,
    --        probe17 => app_wdf_data,
    --        probe18 => app_wdf_end,
    --        probe19 => app_wdf_wren,
    --        probe20 => init_calib_complete,
    --        probe21 => fast_if_state,
    --        probe22 => cpu_req,
    --        probe23 => handled_words,
    --        probe24 => burst_current_address,
    --        probe25 => burst_end_address,
    --        probe26 => stmi_req.burstcnt
    --    );

end behav;
