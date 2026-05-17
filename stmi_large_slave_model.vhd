
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

library stmi_lib;
use stmi_lib.stmi.stmi_req_T;
use stmi_lib.stmi.stmi_ans_T;
use stmi_lib.stmi.WR_MODE;
use stmi_lib.stmi.RD_MODE;
use stmi_lib.stmi.stmi_bcnt_T;
use stmi_lib.stmi.stmi_addr_T;

entity stmi_large_slave_model is
    generic(
        RANDOM_DELAYS: boolean := false;
        INIT_VALS: natural := 0
    );
    port(
        clk     : IN std_logic;
        res_n   : IN std_logic;

        stmi_req   : IN stmi_req_T;
        stmi_ans   : OUT stmi_ans_T
    );
--  Port ( );
end stmi_large_slave_model;

architecture behav of stmi_large_slave_model is
    
    signal we: std_logic;
    signal rdata: std_logic_vector(255 downto 0);
    signal wdata: std_logic_vector(255 downto 0);
    signal raddr: std_logic_vector(23 downto 0);
    signal waddr: std_logic_vector(23 downto 0);
    signal be: std_logic_vector(31 downto 0);

    signal next_addr, current_addr: std_logic_vector(31 downto 0);
    signal current_burstcnt: stmi_bcnt_T;
    signal end_addr: std_logic_vector(31 downto 0);
    type state_T is (IDLE, READING, WRITING);
    signal current_state: state_T;
    signal rng: std_logic_vector(31 downto 0);
    signal handle_request: boolean;
    signal next_sent_words, sent_words: natural;
    signal req_burstcnt: stmi_bcnt_T;
    signal exp_bcnt: stmi_addr_T;


    constant CHECK_BURSTS: boolean := true;
begin
    stmi_ans.rdata <= rdata;
    wdata <= stmi_req.wdata;
    be <= stmi_req.be;


    transaction_state_p: process(clk, res_n) is
        variable tmp_addr: stmi_addr_T;
    begin
        if res_n /= '1' then
            end_addr <= (others => '0');
            current_state <= IDLE;
            current_addr <= (others => '0');
            sent_words <= 0;
            req_burstcnt <= (others => '0');
        else
            if (clk'event and clk = '1') then  
                case current_state is
                    when IDLE => 
                        if stmi_req.req then
                            if stmi_req.mode = RD_MODE then
                                current_state <= READING;
                            else
                                current_state <= WRITING;
                            end if;
                            tmp_addr := (others => '0');
                            tmp_addr(8 downto 5) := stmi_req.burstcnt;
                            tmp_addr := std_logic_vector(unsigned(stmi_req.addr) + unsigned(tmp_addr));
                            end_addr <= tmp_addr;
                            req_burstcnt <= stmi_req.burstcnt;
                        end if;

                    when READING | WRITING => 
                        if stmi_ans.done then
                            current_state <= IDLE;
                        end if;

                        --if stmi_ans.ack and unsigned(current_addr) /= unsigned(end_addr)  then
                        --    current_addr <= std_logic_vector(unsigned(current_addr) + 1);
                        --end if;
                end case;

                current_addr <= next_addr;
                sent_words <= next_sent_words;
            end if;
        end if;
    end process transaction_state_p;

    raddr <= next_addr(28 downto 5);
    waddr <= current_addr(28 downto 5);

    fsm_out_p: process(all) is
    begin
        stmi_ans.ack <= false;
        stmi_ans.done <= false;
        next_addr <= current_addr;
        next_sent_words <= sent_words;

        we <= '0';

        case current_state is
            when IDLE => 
                next_addr <= stmi_req.addr;
                next_sent_words <= 0;

            when WRITING => 
                stmi_ans.done <= current_addr = end_addr and handle_request;
                stmi_ans.ack <= stmi_req.req and handle_request;
                we <= '1' when stmi_req.req and handle_request else
                      '0';

                if handle_request and stmi_req.req then
                    next_addr <= std_logic_vector(unsigned(current_addr) + 32);
                end if;

            when READING => 
                stmi_ans.done <= current_addr = end_addr and handle_request;
                stmi_ans.ack <= handle_request and sent_words /= unsigned(req_burstcnt);

                if handle_request then
                    next_addr <= std_logic_vector(unsigned(current_addr) + 32);
                    next_sent_words <= sent_words + 1;
                end if;

        end case;
    end process fsm_out_p;


    uglyButEfficientRAM : process(clk, raddr) is
        constant storeTypeWidth : positive := 31; -- integers are 31 bits wide (they do not cover the entire range!)
        constant requiredwords : positive := integer(ceil(real(wdata'length) / real(storeTypeWidth)));
        constant INIT_DEPTH: positive := 2**20 / wdata'length;
        
        -- use natural since it should be very memory efficient in simulation
        type intMemArrayT is array(requiredwords - 1 downto 0, 2**raddr'length - 1 downto 0) of integer; 
    
        -- use a variable since it is supposed to use much less memory than a signal for some reason (more than an order of magnitude less)
        variable intMemArray: intMemArrayT := (others => (others => INIT_VALS));
        variable tmp_wdata: std_logic_vector(wdata'range);
    begin
        if clk'event and clk = '1' then
            for i in intMemArray'range(1) loop
                if (i + 1) * storeTypeWidth - 1 < wdata'length then
                    rdata((i + 1) * storeTypeWidth - 1 downto i * storeTypeWidth) <= std_logic_vector(to_signed(intMemArray(i, to_integer(unsigned(raddr))), storeTypeWidth));
                else
                    rdata(rdata'left downto i * storeTypeWidth) <= std_logic_vector(to_signed(intMemArray(i, to_integer(unsigned(raddr))), rdata'length - i * storeTypeWidth));
                end if;
            end loop;

            if we = '1' then
                for i in intMemArray'range(1) loop
                    if (i + 1) * storeTypeWidth - 1 < wdata'length then
                        tmp_wdata((i + 1) * storeTypeWidth - 1 downto i * storeTypeWidth) := std_logic_vector(to_signed(intMemArray(i, to_integer(unsigned(waddr))), storeTypeWidth));
                    else
                        tmp_wdata(tmp_wdata'left downto i * storeTypeWidth) := std_logic_vector(to_signed(intMemArray(i, to_integer(unsigned(waddr))), tmp_wdata'length - i * storeTypeWidth));
                    end if;
                end loop;

                for i in be'range loop
                    if be(i) = '1' then
                        tmp_wdata((i + 1) * 8 - 1 downto i * 8) := wdata((i + 1) * 8 - 1 downto i * 8);
                    end if;
                end loop;

                for i in intMemArray'range(1) loop
                    if (i + 1) * storeTypeWidth - 1 < wdata'length then
                        intMemArray(i, to_integer(unsigned(waddr))) := to_integer(signed(tmp_wdata((i + 1) * storeTypeWidth - 1 downto i * storeTypeWidth)));
                    else
                        intMemArray(i, to_integer(unsigned(waddr))) := to_integer(signed(tmp_wdata(tmp_wdata'left downto i * storeTypeWidth)));
                    end if;
                end loop;
            end if;      
        end if;
    
    end process uglyButEfficientRAM;

    handle_request <= (unsigned(rng(1 downto 0)) = 0 or not RANDOM_DELAYS);
      process(res_n, clk) is
        variable rng_v: std_logic_vector(rng'range);
    begin
        if res_n = '0' then
            rng <= (0 => '1', others => '0');
        else
            if clk'event and clk = '1' then

                rng_v := rng(rng'left - 1 downto rng'right) & '0';
                if rng(rng'left) = '1' then
                    rng_v := rng_v xor x"0FC22F07";
                end if;
                rng <= rng_v;
            end if;
        end if;
    end process;



    -- iburstchk: if CHECK_BURSTS generate
    --     --this burst check mode works on the premise of always following up a write burst with a series of std_logic writes containing the same data

    --     type burst_data_T is array(2**B_CNT_W-1 downto 0) of std_logic_vector(stmi_req.wdata’range);
    --     signal burst_data: burst_data_T;
    --     signal burst_ix: natural range 0 to 2**B_CNT_W-1;


    --     type burst_check_state_T is (IDLE, ACCUMULATING, COMPARING);
    --     signal burst_check_state: burst_check_state_T;
    -- begin
    --     burst_check_state_p: process(clk, res_n) is
    --     begin
    --         if res_n /= '1' then
    --             burst_check_state <= IDLE;
    --             burst_ix <= 0;
    --         else
    --             if (clk'event and clk = '1') then  
    --                 case burst_check_state is
    --                     when IDLE =>
    --                         if stmi_req.req and stmi_req.mode = WR_MODE and unsigned(stmi_req.burstcnt) /= 1 then
    --                             burst_data(0) <= stmi_req.wdata;
    --                             burst_check_state <= ACCUMULATING;
    --                             if stmi_ans.ack then
    --                                 burst_ix <= 1;
    --                             end if;
    --                         end if;
    --                     when ACCUMULATING =>
    --                     when COMPARING => 
    --                 end case;
    --             end if;
    --         end if;
    --     end process burst_check_state_p;
    -- end generate;
end behav;
