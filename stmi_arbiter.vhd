----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 07/21/2025 10:12:30 PM
-- Design Name: 
-- Module Name: stmi_arbiter - Behavioral
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
use IEEE.numeric_std.all;

library stmi_lib;
use stmi_lib.stmi.all;


entity stmi_arbiter is
    generic(
        PORTS: positive
    );
    port(
        clk     : IN std_logic;
        res_n   : IN std_logic;

        s_req   : IN stmi_req_vec_T(PORTS downto 1) := (others => IDLE_STMI_REQ);
        s_ans   : OUT stmi_ans_vec_T(PORTS downto 1);

        m_req   : OUT stmi_req_T;
        m_ans   : IN stmi_ans_T;

        active_port: OUT std_logic_vector(3 downto 0);
        next_active_port: OUT std_logic_vector(3 downto 0);
        in_request_d: OUT boolean

    );
--  Port ( );
end stmi_arbiter;

architecture behav of stmi_arbiter is
    subtype port_id_T is natural range PORTS downto 0;

    type last_serve_id_T is array(stmi_prio_T'high downto stmi_prio_T'low) of port_id_T;
    signal last_serve_id: last_serve_id_T;

    signal active_port_id: port_id_T;
    signal next_active_port_id: port_id_T;
    signal next_serve_port: boolean;
    signal serve_prio: stmi_prio_T;

    signal next_in_request, in_request: boolean;

    signal startup_done: boolean;
    
    type held_rdata_T is  array(port_id_T) of std_logic_vector(m_ans.rdata'range);
    signal held_rdata: held_rdata_T;

    signal any_request: boolean;
begin
    i_passthrough_or_arb: if PORTS = 1 generate
    begin
        m_req <= s_req(1);
        s_ans(1) <= m_ans;
    else generate

        active_port <= std_logic_vector(to_unsigned(active_port_id, active_port'length));
        next_active_port <= std_logic_vector(to_unsigned(next_active_port_id, active_port'length)) when any_request else
                            "0000";


        ans_to_slaves_p: process(all) is
        begin
            for porti in s_ans'range loop
                s_ans(porti).rdata <= (others => '0');
                s_ans(porti).ack <= false;
                s_ans(porti).done <= false;
            end loop;

            if active_port_id /= 0 then
                s_ans(active_port_id).rdata <= m_ans.rdata;
            end if;
            --s_ans(active_port_id).rdata <= m_ans.rdata;
            if active_port_id /= 0 and m_ans.ack then
                s_ans(active_port_id).ack <= m_ans.ack;
                s_ans(active_port_id).done <= m_ans.done;
            end if;
        end process ans_to_slaves_p;

        rdata_hold_p: process(clk, res_n) is
        begin
            if res_n /= '1' then
                held_rdata <= (others => (others => '0'));
            else
                if (clk'event and clk = '1') then 
                    if active_port_id /= 0 then
                        held_rdata(active_port_id) <= m_ans.rdata;
                    end if; 
                end if;
            end if;
        end process rdata_hold_p;



        any_req_p: process(all) is
            variable a_req: boolean;
        begin
            any_request <= false;
            a_req := false;
            for porti in s_req'range loop
                if s_req(porti).req then
                    any_request <= true;
                    a_req := true;
                end if;
            end loop;
            
            m_req <= IDLE_STMI_REQ;
            m_req.addr <= (others => '0');
            m_req.wdata <= (others => '0');

            if startup_done and active_port_id /= 0 then
                m_req <= s_req(active_port_id);
            end if;
        end process any_req_p;




        state_p: process(clk, res_n) is
        begin
            if res_n /= '1' then
                last_serve_id <= (others => port_id_T'low);
                active_port_id <= 0;
                startup_done <= false;
                in_request <= false;
            else
                if (clk'event and clk = '1') then  
                    if next_serve_port then
                        last_serve_id(0) <= next_active_port_id;                      
                    end if;
                    active_port_id <= next_active_port_id;
                    
                    startup_done <= true;
                end if;
            end if;
        end process state_p;


        in_request_d <= in_request;
        next_serve_det_p: process(all) is
            variable highest_prio: stmi_prio_T;
            variable port_search_ix: port_id_T;
            variable next_in_req_int: boolean;
            variable next_active_port_id_int: port_id_T;
        begin
            highest_prio := stmi_prio_T'low;
            next_in_req_int := in_request;
            next_serve_port <= false;
            
            
            for pi in s_req'range loop 
                if s_req(pi).req and s_req(pi).prio > highest_prio then
                    highest_prio := s_req(pi).prio;
                end if;
            end loop;

            next_active_port_id_int := active_port_id;
            serve_prio <= highest_prio;

            if m_ans.done then
                next_active_port_id_int := 0;
            end if;

            if active_port_id = 0 then
                -- serve next port in this prio class
                port_search_ix := 1;
                for i in PORTS + 1 downto 1 loop
                    if next_active_port_id_int = 0 then
                        if port_search_ix = port_id_T'high then
                            port_search_ix := 1;
                        else
                            port_search_ix := port_search_ix + 1;
                        end if;

                        if s_req(port_search_ix).req then
                            next_active_port_id_int := port_search_ix;
                            next_serve_port <= true;
                        end if;
                    end if;

                end loop;
            end if;

            next_in_request <= next_in_req_int;
            next_active_port_id <= next_active_port_id_int;
        end process next_serve_det_p;
        

    end generate i_passthrough_or_arb;

end behav;
