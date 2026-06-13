
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

entity stmi_block_mem_adapter is
    generic(
        AWIDTH: positive
    );
    port(
        clk     : IN std_logic;
        res_n   : IN std_logic;

        stmi_req   : IN stmi_req_T;
        stmi_ans   : OUT stmi_ans_T;

        raddr       : OUT std_logic_vector(AWIDTH - 1 downto 0);
        waddr       : OUT std_logic_vector(AWIDTH - 1 downto 0);
        be         : OUT std_logic_vector(31 downto 0);
        wdata      : OUT std_logic_vector(255 downto 0);
        rdata      : IN std_logic_vector(255 downto 0)
    );
--  Port ( );
end stmi_block_mem_adapter;

architecture behav of stmi_block_mem_adapter is


    signal next_addr, current_addr: std_logic_vector(31 downto 0);
    signal current_burstcnt: stmi_bcnt_T;
    signal end_addr: std_logic_vector(31 downto 0);
    type state_T is (IDLE, READING, WRITING);
    signal current_state: state_T;
    signal rng: std_logic_vector(31 downto 0);
    signal handle_request: boolean;
    signal next_sent_words, sent_words: natural;
    signal req_burstcnt: stmi_bcnt_T;


    constant CHECK_BURSTS: boolean := true;
begin
    stmi_ans.rdata <= rdata;
    wdata <= stmi_req.wdata;
    handle_request <= true;
    


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
                            tmp_addr := std_logic_vector(unsigned(stmi_req.addr) + (unsigned(stmi_req.burstcnt) * 32));
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

    raddr <= next_addr(AWIDTH + 4 downto 5);
    waddr <= current_addr(AWIDTH + 4 downto 5);

    fsm_out_p: process(all) is
    begin
        stmi_ans.ack <= false;
        stmi_ans.done <= false;
        next_addr <= current_addr;
        next_sent_words <= sent_words;
        be <= (others => '0');


        case current_state is
            when IDLE => 
                next_addr <= stmi_req.addr;
                next_sent_words <= 0;

            when WRITING => 
                stmi_ans.done <= current_addr = end_addr and handle_request;
                stmi_ans.ack <= stmi_req.req and handle_request;
                be <= stmi_req.be when stmi_req.req and handle_request else
                      (others => '0');


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
end behav;
