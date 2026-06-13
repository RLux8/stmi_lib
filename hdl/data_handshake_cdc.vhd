----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 01/04/2025 08:13:47 PM
-- Design Name: 
-- Module Name: data_handshake_cdc - Behavioral
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


entity data_handshake_cdc is
    GENERIC(
        AB_WIDTH: positive;
        BA_WIDTH: positive;
        CMD_DEPTH: positive;
        DATA_DEPTH: positive
    );
    PORT(
        a_clk: in std_logic;
        a_res_n: in std_logic;

        a_data_in: in std_logic_vector(AB_WIDTH - 1 downto 0);
        a_data_out: out std_logic_vector(BA_WIDTH - 1 downto 0);
        a_req: in boolean;
        a_ack: out boolean;


        b_clk: in std_logic;
        b_res_n: in std_logic;

        b_data_in: in std_logic_vector(BA_WIDTH - 1 downto 0);
        b_data_out: out std_logic_vector(AB_WIDTH - 1 downto 0);
        b_req: out boolean;
        b_ack: in boolean;
        
        
        dbg_a_req_int: out boolean

    );
end data_handshake_cdc;


architecture Behavioral of data_handshake_cdc is
    signal a_req_int: boolean;
    signal a_ack_int: boolean;
    signal last_a_ack_int: boolean;

    signal b_req_int: boolean;
    signal b_req_q: boolean;
    signal b_ack_int: boolean;

    subtype data_abT is std_logic_vector(a_data_in'range);
    subtype data_baT is std_logic_vector(b_data_in'range);

    signal next_a_ack: boolean;
    signal last_b_ack: boolean;
    signal b_current_data, held_b_data_in: std_logic_vector(b_data_in'range);
begin

    a_to_b_encode_p: process(a_clk, a_res_n) is
        variable in_req: boolean;
        variable startup: boolean;
    begin
        if a_res_n /= '1' then
            in_req := false;
            a_req_int <= false;
            startup := true;
        else
            if (a_clk'event and a_clk = '1') then
                if not startup then  
                    if a_req and not in_req then
                        in_req := true;
                        a_req_int <= not a_req_int;
                    elsif a_ack then
                        in_req := false;
                    end if;
                end if;
                startup := false;
            end if;
        end if;
    end process a_to_b_encode_p;


    a_to_b_sync_p: process(b_clk, b_res_n) is
        type a_data_vec_T is array(DATA_DEPTH downto 1) of data_abT;
        variable a_data_vec: a_data_vec_T;

        type a_req_vec_T is array(CMD_DEPTH downto 1) of boolean;
        variable a_req_vec: a_req_vec_T;
       
    begin
        if b_res_n = '0' then
            b_data_out <= (others => '0');
            b_req_int <= false;

            
            a_req_vec := (others => false);
            a_data_vec := (others => (others => '0'));
        else
            if (b_clk'event and b_clk = '1') then  
                b_data_out <= a_data_vec(DATA_DEPTH);
                b_req_int <= a_req_vec(CMD_DEPTH);

                for i in DATA_DEPTH downto 1 loop 
                    if i = 1 then
                        a_data_vec(i) := a_data_in;
                    else
                        a_data_vec(i) := a_data_vec(i - 1);
                    end if;
                end loop;
                
                for i in CMD_DEPTH downto 1 loop 
                    if i = 1 then
                        a_req_vec(i) := a_req_int;
                    else
                        a_req_vec(i) := a_req_vec(i - 1);
                    end if;
                end loop;

            end if;
        end if;
    end process a_to_b_sync_p;

    
    dbg_a_req_int <= b_req_int;

    a_to_b_decode_p: process(b_clk, b_res_n) is
        variable last_b_req_int: boolean;
    begin
        if b_res_n = '0' then
            b_req_q <= false;
            last_b_req_int := false;
        else
            if (b_clk'event and b_clk = '1') then  
                if b_req_int /= last_b_req_int then
                    b_req_q <= true;
                elsif b_ack then
                    b_req_q <= false;
                end if;

                last_b_req_int := b_req_int;
            end if;
        end if;
    end process a_to_b_decode_p;

    b_req <= b_req_q;



    b_to_a_encode_p: process(b_clk, b_res_n) is
    begin
        if b_res_n /= '1' then
            b_ack_int <= false;
        else
            if (b_clk'event and b_clk = '1') then  
                if b_ack then
                    b_ack_int <= not b_ack_int;
                    last_b_ack <= b_ack;
                    held_b_data_in <= b_data_in;
                end if;
            end if;
        end if;
    end process b_to_a_encode_p;

    
    b_current_data <= b_data_in when b_ack else held_b_data_in;
    
    b_to_a_sync_p: process(a_clk, a_res_n) is
        type b_data_vec_T is array(DATA_DEPTH downto 1) of data_baT;
        variable b_data_vec: b_data_vec_T;

        type b_ack_vec_T is array(CMD_DEPTH downto 1) of boolean;
        variable b_ack_vec: b_ack_vec_T;
    begin
        if a_res_n /= '1' then
            a_data_out <= (others => '0');
            a_ack_int <= false;

            b_ack_vec := (others => false);
            b_data_vec := (others => (others => '0'));
        else
            if (a_clk'event and a_clk = '1') then  
                a_data_out <= b_data_vec(DATA_DEPTH);
                a_ack_int <= b_ack_vec(CMD_DEPTH);

                for i in DATA_DEPTH downto 1 loop 
                    if i = 1 then
                        b_data_vec(i) := b_current_data;
                    else
                        b_data_vec(i) := b_data_vec(i - 1);
                    end if;
                end loop;

                for i in CMD_DEPTH downto 1 loop 
                    if i = 1 then
                        b_ack_vec(i) := b_ack_int;
                    else
                        b_ack_vec(i) := b_ack_vec(i - 1);
                    end if;
                end loop;
            end if;
        end if;
    end process b_to_a_sync_p;


    b_to_a_decode_p: process(a_clk, a_res_n) is
    begin
        if a_res_n /= '1' then
            last_a_ack_int <= false;
            a_ack <= false;
        else
            if (a_clk'event and a_clk = '1') then  
                last_a_ack_int <= a_ack_int;
                a_ack <= next_a_ack;
            end if;
        end if;
    end process b_to_a_decode_p;

    next_a_ack <= a_ack_int /= last_a_ack_int;
end Behavioral;
