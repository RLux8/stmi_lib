----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 07/20/2025 02:52:59 PM
-- Design Name: 
-- Module Name: rv_stmi_adapter - Behavioral
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

library rv64i_lib;
use rv64i_lib.interface.all;
USE rv64i_lib.isa.ALL;

library stmi_lib;
use stmi_lib.stmi.all;


entity cache_stmi_adapter is
    PORT(
        clk                 : IN     single;
        res_n               : IN     single;

        ic_rreq             : IN     boolean;
        ic_raddr            : IN     dword;
        ic_rack             : OUT    boolean;
        ic_rdata            : OUT    bus_type;

        dc_rreq             : IN     boolean;
        dc_raddr            : IN     dword;
        dc_wreq             : IN     boolean;
        dc_waddr            : IN     dword;
        dc_we               : IN     boolean;
        dc_wdata            : IN     bus_type;
        dc_rack             : OUT    boolean;
        dc_wack             : OUT    boolean;
        dc_rdata            : OUT    bus_type;
        dc_be               : IN     std_logic_vector(31 downto 0);

        stmi_req            : OUT     stmi_req_T;
        stmi_ans            : IN      stmi_ans_T
    );
end cache_stmi_adapter;

architecture behav of cache_stmi_adapter is
    type cache_req_type is (idle, ic_read, dc_read, dc_write);
    signal cache_req: cache_req_type;

    signal last_dc_rreq: boolean;
    signal last_dc_wreq: boolean;
    signal last_ic_rreq: boolean;

    signal stmi_req_int: stmi_req_T;
    signal next_transferred_words, transferred_words: natural range 0 to 2;

    signal request_hangup: boolean;

    constant USE_READ_BURSTS: boolean := true;
    constant USE_WRITE_BURSTS: boolean := false;
begin
    -- slow side
    arbiter_slow_state_p: process (clk, res_n) is
    begin
        if res_n = '0' then
            cache_req <= idle;
            stmi_req <= IDLE_STMI_REQ;
            transferred_words <= 0;
        else
            if clk'event and clk = '1' then              
                if stmi_ans.done then
                    cache_req <= idle;
                elsif cache_req = idle then   
                    if dc_wreq then
                        cache_req <= dc_write;
                    elsif ic_rreq then
                        cache_req <= ic_read;
                    elsif dc_rreq then
                        cache_req <= dc_read;
                    end if;
                end if;


                stmi_req <= stmi_req_int;
                transferred_words <= next_transferred_words;
            end if;
        end if;
    end process arbiter_slow_state_p;
    


    dc_rdata <= stmi_ans.rdata;
    ic_rdata <= stmi_ans.rdata;

    arbiter_slow_ouput_p: process(all) is
        variable transferred_words_int: natural range 0 to 2;
    begin
        stmi_req_int.req <= false;
        stmi_req_int.addr <= dc_raddr(stmi_req.addr'range);
        stmi_req_int.wdata <= dc_wdata;
        stmi_req_int.mode <= RD_MODE;
        stmi_req_int.prio <= 2;
        stmi_req_int.be <= dc_be;
        stmi_req_int.burstcnt <= (0 => '1', others => '0');
        dc_wack <= false;
        ic_rack <= false;
        dc_rack <= false;
        transferred_words_int := transferred_words;


        if stmi_ans.ack then
            if transferred_words_int /= 2 then
                transferred_words_int := transferred_words_int + 1;
            end if;

            case cache_req is
                when dc_read => 
                    dc_rack <= true;
                when ic_read => 
                    ic_rack <= true;
                when dc_write => 
                    dc_wack <= true;
                when others => null;
            end case;
        end if;

        case cache_req is
            when idle => 
                transferred_words_int := 0;
                if dc_wreq then
                    stmi_req_int.mode <= WR_MODE;
                    stmi_req_int.be <= dc_be;
                    stmi_req_int.wdata <= dc_wdata;
                    stmi_req_int.addr <= dc_waddr(stmi_req.addr'range);
                    stmi_req_int.req <= true;

                    if USE_WRITE_BURSTS then
                        stmi_req_int.burstcnt <= (1 => '1', others => '0');
                    end if;
                elsif ic_rreq then
                    stmi_req_int.mode <= RD_MODE;
                    stmi_req_int.addr <= ic_raddr(stmi_req.addr'range);
                    stmi_req_int.req <= true;

                    if USE_READ_BURSTS then
                        stmi_req_int.burstcnt <= (1 => '1', others => '0');
                    end if;
                elsif dc_rreq then
                    stmi_req_int.mode <= RD_MODE;
                    stmi_req_int.addr <= dc_raddr(stmi_req.addr'range);
                    stmi_req_int.req <= true;

                    if USE_READ_BURSTS then
                        stmi_req_int.burstcnt <= (1 => '1', others => '0');
                    end if;
                end if;
    
            when dc_write =>
                stmi_req_int.mode <= WR_MODE;
                
                stmi_req_int.wdata <= dc_wdata;
                stmi_req_int.addr <= dc_waddr(stmi_req.addr'range);

                if USE_WRITE_BURSTS then
                    stmi_req_int.burstcnt <= (1 => '1', others => '0');
                    stmi_req_int.req <= transferred_words_int /= 2;
                    stmi_req_int.be <= dc_be when dc_wreq else (others => '0');
                else
                    stmi_req_int.req <= dc_wreq;
                    stmi_req_int.be <= dc_be;
                end if;

            when dc_read =>
                stmi_req_int.mode <= RD_MODE;
                stmi_req_int.addr <= dc_raddr(stmi_req.addr'range);

                if USE_READ_BURSTS then
                    stmi_req_int.burstcnt <= (1 => '1', others => '0');
                    stmi_req_int.req <= transferred_words_int /= 2;
                else
                    stmi_req_int.req <= dc_rreq;
                end if;

            when ic_read => 
                stmi_req_int.mode <= RD_MODE;
                stmi_req_int.addr <= ic_raddr(stmi_req.addr'range);

                if USE_READ_BURSTS then
                    stmi_req_int.burstcnt <= (1 => '1', others => '0');
                    stmi_req_int.req <= transferred_words_int /= 2;
                else
                    stmi_req_int.req <= ic_rreq;
                end if;
        end case;

        next_transferred_words <= transferred_words_int;
    end process arbiter_slow_ouput_p;



    req_hangup_det_p: process(clk, res_n) is
        variable holdc: natural;
    begin
        if res_n /= '1' then
            holdc := 0;
            request_hangup <= false;
        else
            if (clk'event and clk = '1') then  
                request_hangup <= false;
                if dc_rreq then
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

    
    --     imigif_ila : ila_12
    --    PORT MAP(
    --        clk => clk,      

    --        probe0 => ic_rreq,
    --        probe1 => ic_rack,
    --        probe2 => dc_rreq,
    --        probe3 => dc_rack,
    --        probe4 => dc_wreq,
    --        probe5 => dc_wack,
    --        probe6 => cache_req,
    --        probe7 => stmi_req.addr,
    --        probe8 => stmi_req.be,
    --        probe9 => stmi_req.burstcnt,
    --        probe10 => stmi_req.mode,
    --        probe11 => stmi_req.req,
    --        probe12 => stmi_ans.ack,
    --        probe13 => stmi_ans.done,
    --        probe14 => request_hangup

    --    );
end behav;
