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

library a100t_soc_lib;

library stmi_lib;
use stmi_lib.stmi.all;

entity stmi_cdc is
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
end stmi_cdc;

architecture behav of stmi_cdc is
    constant CDC_WIDTH: positive := a_req.wdata'length + a_req.addr'length + a_req.be'length + a_req.burstcnt'length + 1;
    signal a_data_in:std_logic_vector(CDC_WIDTH - 1 downto 0);
    signal a_data_out:std_logic_vector(a_ans.rdata'range);

    signal b_data_in:std_logic_vector(a_ans.rdata'range);
    signal b_data_out:std_logic_vector(CDC_WIDTH - 1 downto 0);

    component data_handshake_cdc
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
    end component;
begin

    a_data_in <= a_req.burstcnt & a_req.mode & a_req.addr & a_req.be & a_req.wdata;
    i_cdc: data_handshake_cdc
        GENERIC MAP(
            AB_WIDTH => CDC_WIDTH,
            BA_WIDTH => a_req.wdata'length,
            CMD_DEPTH => 4,
            DATA_DEPTH => 2
        )
        PORT MAP(
            a_clk => a_clk,
            a_res_n => a_res_n,

            b_clk => b_clk,
            b_res_n => b_res_n,

            a_data_in  => a_data_in,
            a_data_out => a_ans.rdata,
            a_req      => a_req.req,
            a_ack      => a_ans.ack,

            b_data_in  => b_data_in,
            b_data_out => b_data_out,
            b_req      => b_req.req,
            b_ack      => b_ans.ack
        );

    b_req.mode <= b_data_out(b_data_out'high - a_req.burstcnt'length);
    b_req.addr <= b_data_out(b_data_out'high - 1 - a_req.burstcnt'length downto a_req.wdata'high + 1 + a_req.be'length);
    b_req.be <= b_data_out(a_req.be'length - 1 + a_req.wdata'high downto a_req.wdata'high);
    b_req.wdata <= b_data_out(a_req.wdata'range);
    b_req.burstcnt <= (0 => '1', others => '0');--b_data_out(b_data_out'high downto b_data_out'high - a_req.burstcnt'length + 1);

    b_data_in <= b_ans.rdata;
end behav;
