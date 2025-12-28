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
use IEEE.NUMERIC_STD.ALL;

library rv64i_lib;
use rv64i_lib.interface.all;
USE rv64i_lib.isa.ALL;

library stmi_lib;
use stmi_lib.stmi.all;


entity cache_stmi_adapter is
    GENERIC(
        NUM_WRITE_PORTS: natural;
        WRITE_BURST_CNTS: natural_vec_T;

        NUM_READ_PORTS: natural;
        READ_BURST_CNTS: natural_vec_T
    );
    PORT(
        clk                 : IN     single;
        res_n               : IN     single;
        
        rreq                : IN     boolean_vector(NUM_READ_PORTS  downto 1);
        raddr               : IN     addr_vec_T(NUM_READ_PORTS downto 1);
        rdata               : OUT    rdata_vec_T(NUM_READ_PORTS  downto 1);
        rack                : OUT    boolean_vector(NUM_READ_PORTS  downto 1);

        wreq                : IN     boolean_vector(NUM_WRITE_PORTS downto 1);
        waddr               : IN     addr_vec_T(NUM_WRITE_PORTS downto 1);
        wdata               : IN     rdata_vec_T(NUM_WRITE_PORTS downto 1);
        wbe                 : IN     be_vec_T(NUM_WRITE_PORTS  downto 1);
        wack                : OUT    boolean_vector(NUM_WRITE_PORTS downto 1);


        stmi_req            : OUT     stmi_req_T;
        stmi_ans            : IN      stmi_ans_T
    );
end cache_stmi_adapter;

architecture behav of cache_stmi_adapter is
    signal active_port, next_active_port: natural range NUM_READ_PORTS + NUM_WRITE_PORTS downto 0;


    signal stmi_req_int: stmi_req_T;
    signal next_transferred_words, transferred_words: natural range 0 to 8;

    signal request_hangup: boolean;

    constant USE_READ_BURSTS: boolean := true;
    constant USE_WRITE_BURSTS: boolean := false; -- todo: add logic to only burst for ascending write request cache transfers
    constant WRITE_BEFORE_READ: boolean := true;
begin
    -- slow side
    arbiter_slow_state_p: process (clk, res_n) is
    begin
        if res_n = '0' then
            stmi_req <= IDLE_STMI_REQ;
            transferred_words <= 0;
            active_port <= 0;
        else
            if clk'event and clk = '1' then  
                stmi_req <= stmi_req_int;

                if stmi_ans.done then
                    stmi_req <= IDLE_STMI_REQ;
                end if;

                active_port <= next_active_port;
                transferred_words <= next_transferred_words;
            end if;
        end if;
    end process arbiter_slow_state_p;


    state_trans_p: process(all) is
        variable transferred_words_int: natural range 0 to 8;
        variable next_active_port_int: natural range NUM_READ_PORTS + NUM_WRITE_PORTS downto 0;
    begin
        next_active_port_int := active_port;
        transferred_words_int := transferred_words;

        if transferred_words_int /= 8 and stmi_ans.ack then
            transferred_words_int := transferred_words_int + 1;
        end if;

        if stmi_ans.done then
            next_active_port_int := 0;
            transferred_words_int := 0;
        elsif active_port = 0 then
            if WRITE_BEFORE_READ then
                for wi in wreq'low to wreq'high loop
                    if next_active_port_int = 0 then
                        if wreq(wi) then
                            next_active_port_int := wi + NUM_READ_PORTS;
                        end if;
                    end if;
                end loop;
                for ri in rreq'low to rreq'high loop
                    if next_active_port_int = 0 then
                        if rreq(ri) then
                            next_active_port_int := ri;
                        end if;
                    end if;
                end loop;
            else
                for ri in rreq'low to rreq'high loop
                    if next_active_port_int /= 0 then
                        if rreq(ri) then
                            next_active_port_int := ri;
                        end if;
                    end if;
                end loop;
                for wi in wreq'low to wreq'high loop
                    if next_active_port_int /= 0 then
                        if wreq(wi) then
                            next_active_port_int := wi + NUM_READ_PORTS;
                        end if;
                    end if;
                end loop;
            end if;
        end if;


        next_active_port <= next_active_port_int;
        next_transferred_words <= transferred_words_int;
    end process state_trans_p;
    


    

    arbiter_slow_ouput_p: process(all) is
        variable out_port: natural range NUM_READ_PORTS + NUM_WRITE_PORTS downto 0; 
    begin
        stmi_req_int.req <= false;
        stmi_req_int.addr <= (others => 'X');
        stmi_req_int.wdata <= (others => 'X');
        stmi_req_int.mode <= RD_MODE;
        stmi_req_int.prio <= 2;
        stmi_req_int.be <= (others => 'X');
        stmi_req_int.burstcnt <= (0 => '1', others => '0');

        for ri in rreq'range loop
            rack(ri) <= false;
            rdata(ri) <= (others => 'X');
        end loop;

        for wi in wreq'range loop
            wack(wi) <= false;
        end loop;

        if stmi_ans.ack then
            if active_port > NUM_READ_PORTS then
                wack(active_port - NUM_READ_PORTS) <= true;
            elsif active_port > 0 then
                rack(active_port) <= true;
            end if;
        end if;


        if active_port = 0 then
            out_port := next_active_port;
        else
            out_port := active_port;
        end if;


        if active_port = 0 then
            null;
        elsif active_port > NUM_READ_PORTS then
            stmi_req_int.mode <= WR_MODE;
            stmi_req_int.be <= wbe(active_port - NUM_READ_PORTS) when wreq(active_port - NUM_READ_PORTS) else (others => '0');
            stmi_req_int.wdata <= wdata(active_port - NUM_READ_PORTS);
            stmi_req_int.addr <= waddr(active_port - NUM_READ_PORTS);
            stmi_req_int.req <= transferred_words /= WRITE_BURST_CNTS(active_port - NUM_READ_PORTS - 1);
            stmi_req_int.burstcnt <= std_logic_vector(to_unsigned(WRITE_BURST_CNTS(active_port - NUM_READ_PORTS - 1), stmi_req_int.burstcnt'length));
        else
            stmi_req_int.mode <= RD_MODE;
            stmi_req_int.addr <= raddr(active_port);
            stmi_req_int.req <= transferred_words /= READ_BURST_CNTS(active_port - 1);
            stmi_req_int.burstcnt <= std_logic_vector(to_unsigned(READ_BURST_CNTS(active_port - 1), stmi_req_int.burstcnt'length));
        end if;
    

        for ri in rdata'range loop
            rdata(ri) <= stmi_ans.rdata;
        end loop;
    end process arbiter_slow_ouput_p;



    -- req_hangup_det_p: process(clk, res_n) is
    --     variable holdc: natural;
    -- begin
    --     if res_n /= '1' then
    --         holdc := 0;
    --         request_hangup <= false;
    --     else
    --         if (clk'event and clk = '1') then  
    --             request_hangup <= false;
    --             if dc_rreq then
    --                 if holdc = 300 then
    --                     request_hangup <= true;
    --                 else
    --                     holdc := holdc + 1;
    --                 end if;
    --             else
    --                 holdc := 0;
    --             end if;
    --         end if;
    --     end if;
    -- end process req_hangup_det_p;

    
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
