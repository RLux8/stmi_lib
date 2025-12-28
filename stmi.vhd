----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 07/20/2025 03:31:05 PM
-- Design Name: 
-- Module Name: stmi - Behavioral
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
library  ieee;
use ieee.std_logic_1164.all;

package stmi is
    constant WR_MODE: std_logic := '1';
    constant RD_MODE: std_logic := '0';
    subtype stmi_prio_T is natural range 3 downto 0; 

    constant B_CNT_W: natural := 4;
    subtype stmi_bcnt_T is std_logic_vector(B_CNT_W - 1 downto 0);
    constant ONE_BST_CNT: stmi_bcnt_T := (0 => '1', others => '0');
    constant MAX_BST_CNT: stmi_bcnt_T := (others => '1');

    subtype stmi_addr_T is std_logic_vector(31 downto 0); -- byte address

    type stmi_req_T is record 
        addr           :   stmi_addr_T; 
        burstcnt       :   stmi_bcnt_T;
        mode           :   std_logic;
        prio           :   stmi_prio_T;
        req            :   boolean;
        be             :   std_logic_vector(31 downto 0);
        wdata          :   std_logic_vector(255 downto 0);
    end record stmi_req_T;
    constant IDLE_STMI_REQ: stmi_req_T := ((others => 'X'), ONE_BST_CNT, RD_MODE, stmi_prio_T'low, false, (others => 'X'), (others => 'X'));

    type stmi_req_vec_T is array(natural range <>) of stmi_req_T;


    type stmi_ans_T is record
        ack            :   boolean;
        done           :   boolean;
        rdata          :   std_logic_vector(255 downto 0);
    end record stmi_ans_T;
    constant IDLE_STMI_ANS: stmi_ans_T := (false, false, (others => 'X'));

    type stmi_ans_vec_T is array(natural range <>) of stmi_ans_T;

    type natural_vec_T is array(natural range <>) of natural;
    type addr_vec_T is array(natural range <>) of stmi_addr_T;
    type rdata_vec_T is array(natural range <>) of std_logic_vector(255 downto 0);
    type be_vec_T is array(natural range <>) of std_logic_vector(31 downto 0);
end package stmi;