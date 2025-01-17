---------------------------------------------------------------------------------
-- filename: mips.vhd
-- author  : Wolfgang Brandt
-- company : TUHH, Institute of embedded systems
-- revision: 0.1
-- date    : 26/11/15
---------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

use work.mips_pkg.all;
use work.casts.all;

entity mips_controller_task3_pipelining is -- Pipelined MIPS processor

  generic ( DFileName : STRING := "../dmem/isort_pipe";
            IFileName : STRING := "../imem/isort_pipe");
  port ( clk, reset        : in  STD_LOGIC;
         writedata, dataadr: out STD_LOGIC_VECTOR(31 downto 0);
         memwrite          : out STD_LOGIC
       );
end;

architecture struct of mips_controller_task3_pipelining is

  signal zero,
         lez,
         FOUNDJR ,
  --TODO REMOVE
         ltz,
         gtz,
         branch, 
		     WB_branch,
         WB_jump: STD_LOGIC       := '0';
  signal c      : ControlType     := ('0','0','0','0','0','0','0','0','0','0',
                                      '0','0','0','0','0','0',"0000",WORD);
  signal i      : InstructionType := (UNKNOWN, "000000", "00000", "00000", "00000",  --i
                                     "000000", "00000", x"0000", "00" & x"000000");
  signal ID     : IDType := (x"00000000", x"00000000");
  signal EX     : EXType := (
                  ('0','0','0','0','0','0','0','0','0','0','0','0','0','0','0',
                   '0', "0000",WORD),
                  --Opcode,    opc       rd       rt       rs
                  (UNKNOWN, "000000", "00000", "00000", "00000",
                  --Funct    Shamt     Imm     BrTarget
                  "000000", "00000", x"0000", "00" & x"000000"),
                  --wa          a         imm         pc4         rd2        rd2imm
                  "00000",x"00000000",x"00000000",x"00000000",x"00000000",x"00000000");
  signal MA     : MAType := (
                  ('0','0','0','0','0','0','0','0','0','0','0','0','0','0','0',
                   '0',"0000",WORD),
                  (UNKNOWN, "000000", "00000", "00000", "00000",  --i
                  "000000", "00000", x"0000", "00" & x"000000"),
                  "00000",x"00000000",x"00000000",x"00000000",x"00000000",
                  x"00000000",x"00000000",x"00000000",'0','0','0','0');
  signal WB     : WBType := (
                  ('0','0','0','0','0','0','0','0','0','0','0','0','0','0','0',
                   '0',"0000",WORD),
                  "00000",x"00000000",x"00000000");
  signal wa,
         EX_Rd  : STD_LOGIC_VECTOR(4 downto 0) := "00000";
  signal MA_Rd  : STD_LOGIC_VECTOR(4 downto 0) := "00000";
  signal pc, pcjump, pcbranch, nextpc, pc4, pcm12, pcm8, a, signext, b, rd2imm, aluout,
         wd, rd, rd1, rd2, aout, WB_wd, WB_rd,
         IF_ir : STD_LOGIC_VECTOR(31 downto 0) := ZERO32;
  signal forwardA,
         forwardB : ForwardType := FromREG;
  signal WB_Opc  ,WB_Func   : STD_LOGIC_VECTOR(5 downto 0) := "000000";

  signal Stall_disablePC     : STD_LOGIC := '0';
  signal Stall_disablePC2     : STD_LOGIC := '0';
  signal JumpCommandOccuredKeepStalling     : STD_LOGIC_VECTOR(1 downto 0) := "00";

  signal Bubble     : EXType := (
                  ('0','0','0','0','0','0','0','0','0','0','0','0','0','0','0',
                   '0', "0000",WORD),
                  --Opcode,    opc       rd       rt       rs
                  (NOP, "000000", "00000", "00000", "00000",
                  --Funct    Shamt     Imm     BrTarget
                  "000000", "00000", x"0000", "00" & x"000000"),
                  --wa          a         imm         pc4         rd2        rd2imm
                  "00000",x"00000000",x"00000000",x"00000000",x"00000000",x"00000000");

begin

-------------------- Instruction Fetch Phase (IF) -----------------------------
WB_branch <= branch       when rising_edge(clk);
WB_jump   <= WB.c.jump    when rising_edge(clk);
  pc        <= nextpc when rising_edge(clk);

  pc4       <= 	--to_slv(unsigned(pc) + 8) when Stall_disablePC  = '1' and WB_branch = '0' and WB_jump = '0' else
	              to_slv(unsigned(pc) + 4) ;
  pcm12 		<=  to_slv(unsigned(pc) - 12) ;
  pcm8 		<=  to_slv(unsigned(pc) - 4) ;
    --  CODE FOR ACHIEVING BNE TAKEN CORRECTLY
    --  pc4       <= 	to_slv(unsigned(pc) + 4) when (Stall_disablePC  = '1' and (EX.i.Opc = I_NOP.OPC) and (branch = '0')) else
    --                to_slv(unsigned(pc) + 0) when Stall_disablePC  = '1' else
	  --                to_slv(unsigned(pc) + 4) ;

    FOUNDJR <= '1' when (i.mnem = JR);
-- TODO REMOVE
    
  nextpc    <=

	           MA.pcjump      when MA.c.jump  = '1' else -- j / jal jump addr
               MA.pcbranch  when branch     = '1' else -- branch (bne, beq) addr
               MA.a         when MA.c.jr    = '1' else -- jr addr
                pc         when (IF_ir(31 downto 26) = "100011")   else        
                pc         when (IF_ir(31 downto 26) = "000011") or (i.mnem = JAL) or (EX.i.mnem = JAL) or (MA.i.mnem = JAL) else 
                pc         when (IF_ir(31 downto 26) = "000101") or (i.mnem = BNE) or (EX.i.mnem = BNE) or (MA.i.mnem = BNE) else 
                pc         when (IF_ir(31 downto 26) = "000100") or (i.mnem = BEQ) or (EX.i.mnem = BEQ) or (MA.i.mnem = BEQ) else 
                pc         when (IF_ir(31 downto 26) = "000010") or (i.mnem = J) or (EX.i.mnem = J) or (MA.i.mnem = J)        else 
                pc         when ((IF_ir(5 downto  0) = "001000") and (IF_ir(31 downto 26) = "000000" )) or (i.mnem = JR) or (EX.i.mnem = JR) or (MA.i.mnem = JR)        else 
               --pcm12        when Stall_disablePC = '1' and (EX.i.Opc = I_BEQ.OPC or EX.i.Opc = I_BNE.OPC or EX.i.Opc = I_J.OPC or EX.i.Opc = I_JR.OPC or EX.i.Opc = I_JAL.OPC) else -- Stepping 3 steps back if jump or bne
               --pcm8         when ((EX.c.mem2reg = '1') and (ForwardA = fromALUe  or ForwardB = fromALUe))   else


               pc4	;                                   -- pc + 4;

  imem:        entity work.bram  generic map ( INIT =>  (IFileName & ".imem"))
               port map (clk, '0', pc(11 downto 2), (others=>'0'), IF_ir);

-------------------- IF/ID Pipeline Register -----------------------------------
                                                  -- comment below out for BNE TAKEN CORRECTLY!
  ID        <=  (IF_ir, pc) when rising_edge(clk) --and (Stall_disablePC = '0')
 ;-- else		      (IF_ir, nextpc) when rising_edge(clk) and Stall_disablePC  = '1' and (MA.i.Opc = I_BEQ.OPC) and (branch = '1') ;
-- The second line in the code above make the code delete the command that was read in right after the bne command if a branch shall be taken.				   
-- idea: if branch command arrived in MA phase 2 cock cycles later and a branch signal is set (branch will be taken) forget the instruction following the bne command.
    
-------------------- Instruction Decode and register fetch (ID) ----------------

  dec:         entity work.decoder
               port map ( ID.ir, i );

  ctrl:        entity work.control
               port map ( i, c );

  wa        <= i.Rd   when c.regdst = '1' and c.link = '0'  else   -- R-Type
               i.Rt   when c.regdst = '0' and c.link = '0'  else   -- I-Type, lw
               "11111";                                            -- JAL

  rf:          entity work.regfile
               generic map (EDGE => RISING)
               port map ( clk, WB.c.regwr, i.Rs, i.Rt, WB.wa, WB_wd, rd1, rd2);

  signext   <= X"ffff" & i.Imm  when (i.Imm(15) = '1' and c.signext = '1') else
               X"0000" & i.Imm;

  -- a         <= rd1; -- ALU A input multiplexer

  -- b         <= rd2; -- ALU B input multiplexer

-------------------- Multiplexers regarding Forwarding -------------------------
  a <=  rd1 when (ForwardA = fromReg) else
        aluout when (ForwardA = fromALUe) else
        WB_wd when (ForwardA = fromALUm) else
        wd  when (ForwardA = fromMEM);

  b <=  rd2 when (ForwardB = fromReg) else
        aluout when (ForwardB = fromALUe) else
        WB_wd when (ForwardB = fromALUm) else
        wd  when (ForwardB = fromMEM);

-------------------- Hazard Detection and Forward Logic ------------------------

ForwardA <= fromALUe when ( i.Rs /= "00000" and i.Rs = EX.wa and EX.c.regwr = '1' ) else
            fromALUm when ( i.Rs /= "00000" and i.Rs = MA.wa and MA.c.regwr = '1' ) else
            fromMEM  when ( i.Rs /= "00000" and i.Rs = WB.wa and WB.c.regwr = '1' ) else
            fromReg;

ForwardB <= fromALUe when ( i.Rt /= "00000" and i.Rt = EX.wa and EX.c.regwr = '1' ) else
            fromALUm when ( i.Rt /= "00000" and i.Rt = MA.wa and MA.c.regwr = '1' ) else
            fromMEM  when ( i.Rt /= "00000" and i.Rt = WB.wa and WB.c.regwr = '1' ) else
            fromReg;


--if ( (EX.MemRead == 1) // Detect Load in EX stage
--and (ForwardA==1 or ForwardB==1)) then Stall // RAW Hazard
--DisablePC


	--TODO place in correct part in mips_pkg, it doesnt actually belong here
				
				
WB_Opc <= 	MA.i.Opc when rising_edge(clk)			;
WB_Func <= 	MA.i.funct when rising_edge(clk)			;


-- The following logic looks for all kinds of jump comands and orders 3 stalls.
-- EX.MemRead is equal to EX.c.mem2reg ?
				
Stall_disablePC <= 
				
				  '1' when  		((EX.c.mem2reg = '1') 	
      and (ForwardA = fromALUe                                            or ForwardB = fromALUe))            
      or ((EX.i.Opc = I_BEQ.OPC)                                          or (MA.i.Opc = I_BEQ.OPC)     or (WB_Opc = I_BEQ.OPC))           --ok
      or ((EX.i.Opc = I_BNE.OPC)                                          or (MA.i.Opc = I_BNE.OPC)     or (WB_Opc = I_BNE.OPC))           --ok
      or ((EX.i.Opc = I_BLEZ.OPC)                                         or (MA.i.Opc = I_BLEZ.OPC))          
      or (((EX.i.Opc = I_BLTZ.OPC)      and (EX.i.rt = I_BLTZ.rt))        or ((MA.i.Opc = I_BLTZ.OPC)       and (MA.i.rt = I_BLTZ.rt)))  
      or ((EX.i.Opc = I_BGTZ.OPC)                                         or (MA.i.Opc = I_BGTZ.OPC))           
      or ((EX.i.Opc = I_J.OPC)                                            or (MA.i.Opc = I_J.OPC)       or (WB_Opc = I_J.OPC))             --ok
      or ((EX.i.Opc = I_JAL.OPC)                                          or (MA.i.Opc = I_JAL.OPC)     or (WB_Opc = I_JAL.OPC))  
      or (((EX.i.Opc = I_JALR.OPC)      and (EX.i.funct = I_JALR.funct))  or ((MA.i.Opc = I_JALR.OPC)       and (MA.i.funct = I_JALR.funct)))    
      or (((EX.i.Opc = I_JR.OPC)        and (EX.i.funct = I_JR.funct))    or ((MA.i.Opc = I_JR.OPC)         and (MA.i.funct = I_JR.funct))      or ((WB_Opc = I_JR.OPC) and WB_Func = I_JR.funct))
              
-- Some commands have duplicate opc therefore additional information is needed. 
-- TODO TOASK all commands? Or only the ones used in homework?

		else	'0' when   		(ForwardA /= fromALUe)    and (ForwardB /= fromALUe) and (MA.i.Opc = I_LW.OPC) else
      '0' when
          (EX.i.Opc /= I_BEQ.OPC)                                         and (MA.i.Opc /= I_BEQ.OPC) 
      and (EX.i.Opc /= I_BNE.OPC)                                         and (MA.i.Opc /= I_BNE.OPC) 
      and (EX.i.Opc /= I_BLEZ.OPC)                                        and (MA.i.Opc /= I_BLEZ.OPC) 
      and (EX.i.Opc /= I_BLTZ.OPC)                                        and (MA.i.Opc /= I_BLTZ.OPC) 
      and (EX.i.Opc /= I_BGTZ.OPC)                                        and (MA.i.Opc /= I_BGTZ.OPC) 
      and (EX.i.Opc /= I_J.OPC)                                           and (MA.i.Opc /= I_J.OPC) 
      and (EX.i.Opc /= I_JAL.OPC)                                         and (MA.i.Opc /= I_JAL.OPC) 
      and (EX.i.funct /= I_JALR.funct)                                    and (MA.i.funct /= I_JALR.funct)
      and (EX.i.funct /= I_JR.funct)                                      and (MA.i.funct /= I_JR.funct)      
 --   and ((EX.i.Opc /= I_JALR.OPC)     and (EX.i.funct /= I_JALR.funct))   and ((MA.i.Opc /= I_JALR.OPC)     and (MA.i.funct /= I_JALR.funct))
 --   and ((EX.i.Opc /= I_JR.OPC)       and (EX.i.funct /= I_JR.funct))     and ((MA.i.Opc /= I_JR.OPC)       and (MA.i.funct /= I_JR.funct))

      and rising_edge(clk)
      ;
              
-- TODO Check if special reset condition must be met for BLTZ like above also for the setback. 
-- Assumption: It will never reach that state since other commands dont even put '1' on the Stall_disablePC signal

-------------------- TODO SIGNAL JumpCommandOccuredKeepStalling  ---------------
			--	JumpCommandOccuredKeepStalling <= "11" when
			--						(	(IF_ir(31 downto 26) = I_BEQ.Opc) or
			--							(IF_ir(31 downto 26) = I_BNE.Opc) or -- getting it from raw data
			--							(IF_ir(31 downto 26) = I_BLEZ.Opc) or
			--							(IF_ir(31 downto 26) = I_BLTZ.Opc) or
			--							(IF_ir(31 downto 26) = I_BGTZ.Opc) or
			--							( (c.jump = '1') or (c.jr = '1') ) 		) and ( JumpCommandOccuredKeepStalling = "00") and ( rising_edge(clk) )
	--		else

			--	(ID.i.mnem = "beq" )  or (ID.i.mnem = "jal" ) or (ID.i.mnem = "jar" )
			--     or (ID.i.mnem = "j" )    or (ID.i.mnem = "bne" ) or (ID.i.mnem = "bgtz" )
			--     or (ID.i.mnem = "blez" ) or (ID.i.mnem = "bltz" )
	--				( (c.jump = '1') or (c.jr = '1') ) and ( JumpCommandOccuredKeepStalling /= "11" )

	--								"10" when ( JumpCommandOccuredKeepStalling = "11" ) and ( rising_edge(clk) )
	--		else
	--								"01" when ( JumpCommandOccuredKeepStalling = "10" ) and ( rising_edge(clk) )
	--		else
	--								"00" when ( JumpCommandOccuredKeepStalling = "01" ) and ( rising_edge(clk) ) ;



-- TODO MAKE UPPER STUFF CLEAN!!!


-------------------- Multiplexer Stalling ------------- ------------------------
-- bubble = '0'

  EX  <= Bubble when Stall_disablePC = '1' and rising_edge(clk) else
         (c, i, wa, a, b, signext, ID.pc4, rd2)  when rising_edge(clk);


-------------------- ID/EX Pipeline Register -----------------------------------

--  EX        <= (c, i, wa, a, b, signext, ID.pc4, rd2) when rising_edge(clk);

-------------------- Execution Phase (EX) --------------------------------------

  rd2imm    <= EX.imm when EX.c.alusrc ='1' else
               EX.b;

  alu_inst:    entity work.alu(withBarrelShift)
               port map ( EX.a, rd2imm, EX.c.aluctrl, EX.i.Shamt, aluout,
                          zero, lez, ltz, gtz);

  -- Effective address calculation
  pcbranch  <= to_slv(signed(EX.pc4) + signed(EX.imm(29 downto 0) & "00"));

  pcjump    <= EX.pc4(31 downto 28) & EX.i.BrTarget & "00";



-------------------- EX/MA Pipeline Register -----------------------------------

  MA       <= (EX.c, EX.i, EX.wa, EX.a, EX.imm, EX.pc4, EX.rd2,
               pcbranch, pcjump, aluout, zero, lez, ltz, gtz)
               when rising_edge(clk);

-------------------- Memory Access Phase (MA) ----------------------------------

  wd        <= MA.rd2; --b;
  aout      <= MA.aluout;

  branch    <= '1'  when (MA.i.Opc = I_BEQ.Opc  and     MA.zero = '1') or
                         (MA.i.Opc = I_BNE.Opc  and not MA.zero = '1') or
                         (MA.i.Opc = I_BLEZ.Opc and     MA.lez  = '1') or
                         (MA.i.Opc = I_BLTZ.Opc and     MA.ltz  = '1') or
                         (MA.i.Opc = I_BGTZ.Opc and     MA.gtz  = '1') else
               '0';

  dmem:        entity work.bram_be   -- data memory
               generic map ( EDGE => Falling, FNAME => DFileName)
               port    map ( clk, MA.c, aout(12 downto 0), wd, WB_rd);

-------------------- MA/WB Pipeline Register -----------------------------------

  WB        <= (MA.c, MA.wa, MA.pc4, aout) when falling_edge(clk);
	  
   Stall_disablePC2     <=  Stall_disablePC when rising_edge(clk);

-------------------- Write back Phase (WB) -------------------------------------

  WB_wd     <= WB_rd   when WB.c.mem2reg = '1' and WB.c.link = '0' else -- from DMem
               WB.aout when WB.c.mem2reg = '0' and WB.c.link = '0' else -- from ALU
               WB.pc4;                                                  -- ret. Addr

  writedata <= wd;
  dataadr   <= aout;
  memwrite  <= c.memwr;

end;
