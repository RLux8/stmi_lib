----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 07/20/2025 04:11:01 PM
-- Design Name: 
-- Module Name: stmi_cdc - behav
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

library a100t_soc_lib;

library stmi_lib;
use stmi_lib.stmi.all;

entity stmi_cdc_fifo is
    PORT(
        a_clk       : IN std_logic;
        a_res_n     : IN std_logic;

        b_clk       : IN std_logic;
        b_res_n     : IN std_logic;

        a_req       : IN stmi_req_T;
        a_ans       : OUT stmi_ans_T;

        b_req       : OUT stmi_req_T;
        b_ans       : IN stmi_ans_T;

        a_dbg       : OUT boolean
    );
end stmi_cdc_fifo;

architecture mixed of stmi_cdc_fifo is
    COMPONENT two_clock_288_fifo IS
    PORT (
        rst : IN STD_LOGIC;
        wr_clk : IN STD_LOGIC;
        rd_clk : IN STD_LOGIC;
        din : IN STD_LOGIC_VECTOR(287 DOWNTO 0);
        wr_en : IN STD_LOGIC;
        rd_en : IN STD_LOGIC;
        dout : OUT STD_LOGIC_VECTOR(287 DOWNTO 0);
        full : OUT STD_LOGIC;
        empty : OUT STD_LOGIC
    );
    END COMPONENT;

    COMPONENT two_clock_256_bit_fifo IS
    PORT (
        rst : IN STD_LOGIC;
        wr_clk : IN STD_LOGIC;
        rd_clk : IN STD_LOGIC;
        din : IN STD_LOGIC_VECTOR(255 DOWNTO 0);
        wr_en : IN STD_LOGIC;
        rd_en : IN STD_LOGIC;
        dout : OUT STD_LOGIC_VECTOR(255 DOWNTO 0);
        full : OUT STD_LOGIC;
        empty : OUT STD_LOGIC
    );
    END COMPONENT;
    
    type a_serialise_state_T is (IDLE, SENDING_DATA, AWAITING_COMPLETE, READING);
    signal a_serialise_state: a_serialise_state_T;
    signal next_a_serialised_words, a_serialised_words: stmi_bcnt_T;

    constant FIFO_WIDTHS: positive := a_req.wdata'length + a_req.be'length;

    signal atob_din: std_logic_vector(FIFO_WIDTHS - 1 downto 0);
    signal atob_dout: std_logic_vector(FIFO_WIDTHS - 1 downto 0);
    signal atob_wen: std_logic;
    signal atob_ren: std_logic;
    signal atob_full: std_logic;
    signal atob_empty: std_logic;
    signal atob_cmd_word: std_logic_vector(atob_dout'range);



    type b_serialise_state_T is (IDLE, READING, WRITING, WRITE_PULL_LAST);
    signal b_serialise_state: b_serialise_state_T;
    signal b_serialised_words: stmi_bcnt_T;

    signal btoa_din: std_logic_vector(255 downto 0);
    signal btoa_dout: std_logic_vector(255 downto 0);
    signal btoa_wen: std_logic;
    signal btoa_ren: std_logic;
    signal btoa_full: std_logic;
    signal btoa_empty: std_logic;
    
    constant mode_in_xfer_word: natural := 0;
    subtype burstcnt_in_xfer_word is natural range a_req.burstcnt'length downto 1;
    subtype addr_in_xfer_word is natural range a_req.addr'length - 1 + a_req.burstcnt'length downto a_req.burstcnt'length;
    subtype wdata_in_xfer_word is natural range a_req.wdata'range;
    subtype be_in_xfer_word is natural range a_req.wdata'length + a_req.be'length - 1 downto a_req.wdata'length;

    signal request_hangup: boolean;
begin

    a_serialise_ctrl_p: process(a_clk, a_res_n) is
    begin
        if a_res_n /= '1' then
            a_serialise_state <= IDLE;  
        else
            if (a_clk'event and a_clk = '1') then 
                a_serialised_words <= next_a_serialised_words;

                case a_serialise_state is
                    when IDLE  => 
                        if a_req.req and atob_full = '0' then
                            if a_req.mode = WR_MODE then
                                a_serialise_state <= SENDING_DATA;
                            else
                                a_serialise_state <= READING;
                            end if;
                        end if;
                        a_serialised_words <= (others => '0');

                    when SENDING_DATA => 
                        if next_a_serialised_words = a_req.burstcnt then
                            a_serialise_state <= AWAITING_COMPLETE;
                        end if;
                                    
                    when AWAITING_COMPLETE => 
                        if btoa_empty = '0' then
                            a_serialise_state <= IDLE;
                        end if;

                    when READING => 
                        if next_a_serialised_words = a_req.burstcnt then
                            a_serialise_state <= IDLE;
                        end if;
                end case; 
            end if;
        end if;
    end process a_serialise_ctrl_p;


    a_serialise_output_p: process(all) is
    begin
        atob_din    <= (others => 'Z');
        atob_wen    <= '0';
        a_ans       <= IDLE_STMI_ANS;
        btoa_ren    <= '0';
        next_a_serialised_words <= a_serialised_words;

        case a_serialise_state is
            when IDLE  => 
                atob_din <= (others => '0');
                atob_din(mode_in_xfer_word) <= a_req.mode;
                atob_din(burstcnt_in_xfer_word) <= a_req.burstcnt;
                atob_din(addr_in_xfer_word) <= a_req.addr;
                next_a_serialised_words <= (others => '0');


                if a_req.req then
                    atob_wen <= not atob_full;
                end if;

            when SENDING_DATA => 
                atob_din(wdata_in_xfer_word) <= a_req.wdata;
                atob_din(be_in_xfer_word) <= a_req.be;

                a_ans.ack <= atob_full = '0' and a_req.req;
                atob_wen <= '1' when a_req.req else
                            '0';


                if atob_full = '0' and a_req.req then
                    next_a_serialised_words <= std_logic_vector(unsigned(a_serialised_words) + 1);
                end if;
                
                            
            when AWAITING_COMPLETE => 
                a_ans.done <= btoa_empty = '0';
                btoa_ren <= not btoa_empty;
            
            when READING => 
                a_ans.rdata <= btoa_dout(wdata_in_xfer_word);
                a_ans.ack <= btoa_empty = '0';
                a_ans.done <= btoa_empty = '0' and next_a_serialised_words = a_req.burstcnt;

                btoa_ren <= '1';

                if btoa_empty  = '0' then
                    next_a_serialised_words <= std_logic_vector(unsigned(a_serialised_words) + 1);
                end if;


        end case;
    end process a_serialise_output_p;

    iatob: two_clock_288_fifo
        PORT MAP(
            wr_clk => a_clk,
            rd_clk => b_clk,
            rst => not a_res_n,

            din => atob_din,
            wr_en => atob_wen,
            full => atob_full,

            dout => atob_dout,
            rd_en => atob_ren,
            empty => atob_empty
        );
    
    ibtoa: two_clock_256_bit_fifo
        PORT MAP(
            wr_clk => b_clk,
            rd_clk => a_clk,
            rst => not b_res_n,

            din => btoa_din,
            wr_en => btoa_wen,
            full => btoa_full,

            dout => btoa_dout,
            rd_en => btoa_ren,
            empty => btoa_empty
        );



    b_deser_state_p: process(b_clk, b_res_n) is
    begin
        if b_res_n /= '1' then
            atob_cmd_word <= (others => '0');
            b_serialised_words <= (others => '0');
            b_serialise_state <= IDLE;
        else
            if (b_clk'event and b_clk = '1') then  
                case b_serialise_state is
                    when IDLE =>
                        -- we got a new command via the fifo
                        if atob_empty = '0' then
                            atob_cmd_word <= atob_dout;

                            if atob_dout(mode_in_xfer_word) = RD_MODE then
                                b_serialise_state <= READING;
                            else
                                b_serialise_state <= WRITING;
                            end if;
                        end if;

                        b_serialised_words <= (others => '0');

                    when READING => 
                        if b_ans.ack then
                            b_serialised_words <= std_logic_vector(unsigned(b_serialised_words) + 1);
                        end if;

                        if b_ans.done then
                            b_serialise_state <= IDLE;
                        end if;

                    when WRITING => 
                        if b_ans.ack then
                            b_serialised_words <= std_logic_vector(unsigned(b_serialised_words) + 1);
                        end if;

                        if b_ans.done then
                            b_serialise_state <= WRITE_PULL_LAST;
                        end if;  
                    when WRITE_PULL_LAST =>
                        b_serialised_words <= (others => '0');
                        b_serialise_state <= IDLE;
                end case;
            end if;
        end if;
    end process b_deser_state_p;


    b_deser_output_p: process(all) is
    begin
        b_req <= IDLE_STMI_REQ;
        b_req.addr <= atob_cmd_word(addr_in_xfer_word);
        b_req.mode <= atob_cmd_word(mode_in_xfer_word);
        b_req.burstcnt <= atob_cmd_word(burstcnt_in_xfer_word);


        btoa_din <= b_ans.rdata;
        atob_ren <= '0';
        btoa_wen <= '0';

        case b_serialise_state is
            when IDLE => 

                if atob_dout(mode_in_xfer_word) = RD_MODE and atob_empty = '0' and btoa_full = '0' then
                    b_req.addr <= atob_dout(addr_in_xfer_word);
                    b_req.mode <= atob_dout(mode_in_xfer_word);
                    b_req.burstcnt <= atob_dout(burstcnt_in_xfer_word);
                    b_req.req <= true;
                elsif atob_dout(mode_in_xfer_word) = WR_MODE and atob_empty = '0' then
                    -- get first data word
                    atob_ren <= '1';
                end if;

                atob_ren <= not atob_empty;
            when READING => 
                b_req.req <= b_serialised_words /= b_req.burstcnt and btoa_full = '0';
                btoa_wen <= '1' when b_ans.ack else
                            '0';
                
                -- get next command from atob fifo
                --atob_ren <= '1' when b_ans.done;

            when WRITING => 
                b_req.req <= b_serialised_words /= b_req.burstcnt and atob_empty = '0';
                b_req.wdata <= atob_dout(wdata_in_xfer_word);
                b_req.be <= atob_dout(be_in_xfer_word);

                atob_ren <= '1' when b_ans.ack;
                btoa_wen <= '1' when b_ans.done else
                            '0';

            when WRITE_PULL_LAST => 
                atob_ren <= '1';

        end case;
    end process b_deser_output_p;

    
    req_hangup_det_p: process(b_clk, b_res_n) is
        variable holdc: natural;
    begin
        if b_res_n /= '1' then
            holdc := 0;
            request_hangup <= false;
        else
            if (b_clk'event and b_clk = '1') then  
                request_hangup <= false;
                if a_serialise_state /= IDLE then
                    if holdc = 300 then
                        request_hangup <= true;
                    else
                        holdc := holdc + 1;
                    end if;
                else
                    holdc := 0;
                end if;
            end if;
        end if;
    end process req_hangup_det_p;


    --     imigif_ila : ila_11
    --    PORT MAP(
    --        clk => b_clk,      

    --        probe0 => a_req.req,
    --        probe1 => a_ans.ack,
    --        probe2 => a_ans.done,
    --        probe3 => a_serialise_state,
    --        probe4 => a_serialised_words,
    --        probe5 => b_req.req,
    --        probe6 => b_ans.ack,
    --        probe7 => b_ans.done,
    --        probe8 => b_serialise_state,
    --        probe9 => b_serialised_words,
    --        probe10 => a_req.burstcnt,
    --        probe11 => b_req.burstcnt,
    --        probe12 => b_req.be,
    --        probe13 => b_req.mode,
    --        probe14 => atob_ren,
    --        probe15 => atob_wen,
    --        probe16 => atob_full,
    --        probe17 => atob_empty,
    --        probe18 => btoa_ren,
    --        probe19 => btoa_wen,
    --        probe20 => btoa_full,
    --        probe21 => btoa_empty,
    --        probe22 => request_hangup
    --    );
end mixed;
