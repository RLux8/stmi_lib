----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 07/26/2025 05:33:30 PM
-- Design Name: 
-- Module Name: stmi_fifo_if - behav
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


entity stmi_fifo_if is
    port(
        clk, res_n  : IN std_logic;

        stmi_req    : OUT stmi_req_T;
        stmi_ans    : IN  stmi_ans_T := IDLE_STMI_ANS;

        start_addr  : IN stmi_addr_T := X"44000000";
        total_words : IN stmi_addr_T := X"0000FD1F";
        burst_words : IN stmi_bcnt_T := X"10";
        repeat      : IN boolean := true;
        start       : IN boolean := false;

        use_next    : OUT boolean; 


        fifo_full   : IN std_logic;
        fifo_fill   : OUT std_logic;
        fifo_wdata  : OUT std_logic_vector(255 downto 0);
        fifo_clk    : OUT std_logic
    );
end stmi_fifo_if;



architecture behav of stmi_fifo_if is
    signal filling_active: boolean;
    signal remaining_words: stmi_addr_T;
    signal current_addr: stmi_addr_T;

    signal requesting: boolean;
begin
    stmi_req.prio       <= 3; --//TODO: maybe we should find a smarter way based on fifo fill level?
    stmi_req.req        <= requesting; -- make sure we only start requesting again after updating the address
    stmi_req.addr       <= current_addr;
    stmi_req.mode       <= RD_MODE;
    stmi_req.burstcnt   <= burst_words;

    fifo_fill           <= '1' when stmi_ans.ack else 
                           '0';
    
    fifo_wdata          <= stmi_ans.rdata;


    fifo_clk            <= clk;

    state_p: process(clk, res_n) is
        variable initial_wait: natural;
    begin
        if res_n /= '1' then
            current_addr <= X"40300000";
            remaining_words <= X"0000FD20";
            initial_wait := 0;
            filling_active  <= false;
            requesting <= false;
            use_next <= false;
        else
            if (clk'event and clk = '1') then 
                if initial_wait /= 1_000 then
                    initial_wait := initial_wait + 1;
                else
                    filling_active  <= true;-- test value
                end if;
                
                if to_integer(unsigned(remaining_words)) /= 0 then
                    if stmi_ans.ack then
                        current_addr <= std_logic_vector(unsigned(current_addr) + 32);
                        remaining_words <= std_logic_vector(unsigned(remaining_words) - 1);
                    end if;

                    if stmi_ans.done then
                        requesting <= false;
                    end if;
                else
                    current_addr <= start_addr;
                    remaining_words <= total_words;
                    
                    if not repeat then
                        requesting <= start;
                    else
                        use_next <= not use_next;
                        requesting <= true;
                    end if;

                    
                end if;
                
                if filling_active and fifo_full = '0' then
                    requesting <= true;
                end if;
            end if;
        end if;
    end process state_p;
    
    

end behav;