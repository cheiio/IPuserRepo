----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 08.10.2015 10:51:05
-- Design Name: 
-- Module Name: motorDriver - Behavioral
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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

-- This blocks receives a value between -255 and 255 in order to control a motor pwm and direction

entity motorDriver is
    GENERIC(
            sys_clk         : INTEGER := 50_000_000; --system clock frequency in Hz
            pwm_freq        : INTEGER := 31_372;    --PWM switching frequency in Hz
            nMOTORS         : integer := 3;			-- 7 motors
            bits_resolution : INTEGER := 10;         -- bits of resolution setting the duty cycle
            motor_addr_with : INTEGER := 4;         
            
            -- Width of S_AXI data bus
            C_S_AXI_DATA_WIDTH    : integer    := 32;
            -- Width of S_AXI address bus
            C_S_AXI_ADDR_WIDTH    : integer    := 4
            );
    Port ( 
        -- clock and reset
        S_AXI_ACLK    : in std_logic;
        S_AXI_ARESETN : in std_logic;
        -- write data channel
        S_AXI_WDATA  : in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        SLV_REG_WREN  : in std_logic;
        -- address channel 
        AXI_AWADDR    : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        --motorADDR     : in integer range 0 to nMotors-1;
        -- my inputs / outputs --
        -- output
        PWM_OUT   : out std_logic_vector((nMOTORS*2)-1 downto 0)
        
        );
end motorDriver;

architecture Behavioral of motorDriver is

--ROM for storing the sine values generated by MATLAB.

component pwm is
    GENERIC(
              sys_clk         : INTEGER := 50_000_000; --system clock frequency in Hz
              pwm_freq        : INTEGER := 31_372;    --PWM switching frequency in Hz
              bits_resolution : INTEGER := 4;          --bits of resolution setting the duty cycle
              phases          : INTEGER := 7         --number of output pwms and phases
              );
	Port (    
	          clk       : IN  STD_LOGIC;                                    --system clock
              reset_n   : IN  STD_LOGIC;                                    --asynchronous reset
              ena       : IN  STD_LOGIC;                                    --latches in new duty cycle
              duty      : IN  STD_LOGIC_VECTOR(bits_resolution-1 DOWNTO 0); --duty cycle
              phase     : IN  integer range 0 to nMotors-1;               --pwm phases
              pwm_out   : OUT STD_LOGIC_VECTOR(nMotors-1 DOWNTO 0);                  --pwm outputs
              pwm_n_out : OUT STD_LOGIC_VECTOR(nMotors-1 DOWNTO 0)                   --pwm inverse outputs
              );         
end component;

constant zero : std_logic_vector (bits_resolution-1 DOWNTO 0) := (OTHERS => '0');

signal myMotorADDR : integer range 0 to nMotors-1 := 0;                       --pwm outputs
signal tmp_myMotorADDR : std_logic_vector(3 downto 0) := (others=>'0') ;                       --pwm outputs
signal width1 : STD_LOGIC_VECTOR(bits_resolution-1 DOWNTO 0) := (OTHERS => '0');
signal width2 : STD_LOGIC_VECTOR(bits_resolution-1 DOWNTO 0) := (OTHERS => '0');
signal ena1 : STD_LOGIC := '0';
signal ena2 : STD_LOGIC := '0';
signal signalIn : STD_LOGIC_VECTOR(bits_resolution-1 DOWNTO 0) := (OTHERS => '0');
signal sgn : STD_LOGIC := '0';

signal pwmCH1 : STD_LOGIC_VECTOR(nMotors-1 DOWNTO 0) := (OTHERS => '0');
signal pwmCH2 : STD_LOGIC_VECTOR(nMotors-1 DOWNTO 0) := (OTHERS => '0');

type t_state is (IDLE, work, pass);
signal state: t_state := IDLE;

begin

pwm1: pwm
        generic map(
          sys_clk => sys_clk,
          pwm_freq => pwm_freq,
          bits_resolution =>  bits_resolution,
          phases => nMotors 
        )
        port map(     
            clk => S_AXI_ACLK,
            reset_n => S_AXI_ARESETN,
            ena => ena1,
            duty => width1,
            phase => myMotorADDR,
            pwm_out => open,
            pwm_n_out => pwmCH1
        );
pwm2: pwm
        generic map(
            sys_clk => sys_clk,
            pwm_freq => pwm_freq,
            bits_resolution =>  bits_resolution,
            phases => nMotors 
        )
         
        port map(     
            clk => S_AXI_ACLK,
            reset_n => S_AXI_ARESETN,
            ena => ena2,
            duty => width2,
            phase => myMotorADDR,
            pwm_out =>  open,
            pwm_n_out => pwmCH2
        );
                        
process(S_AXI_ACLK)
begin
	if rising_edge(S_AXI_ACLK) then
	   if S_AXI_ARESETN = '0' then 
	       ena1 <= '0';
	       width1 <= (OTHERS => '0');
           ena2 <= '0';
           width2 <= (OTHERS => '0');
           state <= IDLE;
       else
        case state is
            when IDLE =>
                ena1 <= '0';
                ena2 <= '0';    
                if (SLV_REG_WREN='1' and AXI_AWADDR="0000") then  
                    state <= work;
                    myMotorADDR <= TO_INTEGER(unsigned(S_AXI_WDATA( motor_addr_with - 1 downto 0))); 
                    sgn <= S_AXI_WDATA          (C_S_AXI_DATA_WIDTH-1);
                    signalIn <= S_AXI_WDATA     ((motor_addr_with + bits_resolution) - 1 DOWNTO motor_addr_with);
                    
                end if;
                
            when work =>
                if myMotorADDR < nMOTORS then
                    if signalIn = zero then
                      width1 <= (OTHERS => '0');
                      width2 <= (OTHERS => '0'); 
                    elsif sgn = '0' then
                      width1 <= (OTHERS => '0');
                      width2 <= signalIn;
                    else
                      width1 <= std_logic_vector(unsigned(not(signalIn)) + 1);
                      width2 <= (OTHERS => '0');
                    end if;
                    state <= pass;
                else
                    state <= IDLE;
                end if;
            
            when pass =>
                ena1 <= '1';
                ena2 <= '1';  
                state <= IDLE;
               
            when others => state <= IDLE;
         end case;
         
         FOR i IN 0 to nMotors-1 LOOP                                            --control outputs for each phas
             PWM_OUT(i*2)       <= pwmCH1(i);
             PWM_OUT(i*2 + 1)   <= pwmCH2(i);
         END LOOP;
         
        end if;
	end if;
end process;

end Behavioral;