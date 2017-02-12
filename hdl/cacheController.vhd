--------------------------------------------------------------------------------
-- filename : cacheController.vhd
-- author   : Hoppe
-- company  : TUHH
-- revision : 0.1
-- date     : 24/01/17
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;

entity cacheController is
	generic(
		MEMORY_ADDRESS_WIDTH : INTEGER := 32; -- Memory address is 32-bit wide.
		DATA_WIDTH           : INTEGER := 32; -- Length of instruction/data words.
		BLOCKSIZE            : INTEGER := 4; -- Number of words that a block contains.
		ADDRESSWIDTH         : INTEGER := 256; -- Number of cache blocks.
		OFFSET               : INTEGER := 8; -- Number of bits that can be selected in the cache.
		TAG_FILENAME         : STRING  := "../imem/tagCache";
		DATA_FILENAME        : STRING  := "../imem/dataCache"
	);

	port(
		hitCounter  : out   INTEGER;
		missCounter : out   INTEGER;
		clk         : in    STD_LOGIC;
		reset       : in    STD_LOGIC;
		stallCPU    : out   STD_LOGIC;
		rdCPU       : in    STD_LOGIC;
		wrCPU       : in    STD_LOGIC;
		addrCPU     : in    STD_LOGIC_VECTOR(MEMORY_ADDRESS_WIDTH - 1 downto 0);
		dataCPU_in : in STD_LOGIC_VECTOR( DATA_WIDTH-1 downto 0 );
		dataCPU_out : out STD_LOGIC_VECTOR( DATA_WIDTH - 1 downto 0 );
		readyMEM    : in    STD_LOGIC;
		rdMEM       : out   STD_LOGIC;
		wrMEM       : out   STD_LOGIC;
		addrMEM     : out   STD_LOGIC_VECTOR(MEMORY_ADDRESS_WIDTH - 1 downto 0);
		dataMEM     : inout STD_LOGIC_VECTOR(DATA_WIDTH * BLOCKSIZE- 1 downto 0)
	);

end;



architecture synth of cacheController is
	
	
	type statetype is (
		IDLE,
		CW,
		CMW,
		WBW,
		WCW,
		WRITE,
		CR,
		CMR,
		WBR,
		WCR
	);

	signal state     : statetype := IDLE;
	signal nextstate : statetype := IDLE;

	signal cacheHit : STD_LOGIC := '0';
	signal isDirty  : STD_LOGIC := '0'; 

	signal dataMEMIn        : STD_LOGIC_VECTOR(MEMORY_ADDRESS_WIDTH - 1 downto 0) := (others => '0');
	signal dataMEMOut       : STD_LOGIC_VECTOR(MEMORY_ADDRESS_WIDTH - 1 downto 0) := (others => '0');
	--signal dataMEM			: STD_LOGIC_VECTOR(OFFSET -1 downto 0) := (others => '0');
	signal rd               : STD_LOGIC                                           := '0';
	signal wr               : STD_LOGIC                                           := '0';
	signal valid            : STD_LOGIC                                           := '0';
	 signal hit              : STD_LOGIC                                           := '0';
	signal wrCacheBlockLine : STD_LOGIC                                           := '0';

	signal setValid : STD_LOGIC := '0';
	signal setDirty : STD_LOGIC := '0';

	signal rHitCounter  : INTEGER := 0;
	signal rMissCounter : INTEGER := 0;

	signal dirty_in : STD_LOGIC := '0';
	signal dirty_out : STD_LOGIC := '0';
	signal directMappedCache_data_out : STD_LOGIC_VECTOR( DATA_WIDTH-1 downto 0 ) := (others => '0');
	
	signal cacheBlockLine_in : STD_LOGIC_VECTOR(DATA_WIDTH * BLOCKSIZE- 1 downto 0) := (others => '0');
	signal cacheBlockLine_out : STD_LOGIC_VECTOR(DATA_WIDTH * BLOCKSIZE- 1 downto 0) := (others => '0');
begin
	rHitCounter  <= 0 when reset = '1' and rising_edge(clk) else 
					rHitCounter+1 when state=CW and cacheHit='1' and rising_edge(clk) else
					rHitCounter+1 when state=CR and cacheHit='1' and rising_edge(clk) ;
	rMissCounter <= 0 when reset = '1' and rising_edge(clk) else
					rMissCounter+1 when state=CW and cacheHit='0' and rising_edge(clk) else
					rMissCounter+1 when state=CR and cacheHit='0' and rising_edge(clk) ;

	missCounter <= rMissCounter;
	
	cacheBlockLine_in <= dataMEM;

	addrMEM <= addrCPU;
	
	cache : entity work.directMappedCache
		generic map(
			MEMORY_ADDRESS_WIDTH => MEMORY_ADDRESS_WIDTH,
			DATA_WIDTH           => DATA_WIDTH,
			BLOCKSIZE            => BLOCKSIZE,
			ADDRESSWIDTH         => ADDRESSWIDTH,
			OFFSET               => OFFSET,
			TagFileName          => TAG_FILENAME,
			DataFileName         => DATA_FILENAME
		)
		port map(clk              => clk,
			     reset            => reset,
			     dataCPU_in       => dataCPU_in,
			     dataCPU_out      => directMappedCache_data_out,
			     addrCPU          => addrCPU,
			     dataMEM          => dataMEM,
			     rd               => rd,
			     wr               => wr,
			     valid            => valid,
			     dirty_in		  => dirty_in,
			     dirty_out		  => dirty_out,
			     hit              => hit,
			     setValid         => setValid,
			     setDirty         => setDirty,
			     cacheBlockLine_in => cacheBlockLine_in,
			     cacheBlockLine_out => cacheBlockLine_out,
			     wrCacheBlockLine => wrCacheBlockLine
		);

	-- state register
	state <= IDLE when reset = '1' else nextstate when rising_edge(clk);

	transition_logic : process(clk, state, wrCPU, rdCPU, cacheHit)
	begin
		case state is
			when IDLE =>
				if wrCPU = '1' then
					nextstate <= CW;
				elsif rdCPU = '1' then
					nextstate <= CR;
				end if;

			when CW =>
				if cacheHit = '1' then
					nextstate <= IDLE;
				elsif cacheHit='0'  and valid='0' then
					nextstate <= WCW;
				elsif cacheHit = '0' and valid='1' then
					nextstate <= CMW;
				end if;

			when CMW =>
				if isDirty = '1' then
					nextstate <= WBW;
				elsif isDirty = '0' then
					nextstate <= WCW;
				end if;

			when WBW =>
				if readyMEM = '0' then
					nextstate <= WBW;
				elsif readyMEM = '1' then
					nextstate <= WCW;
				end if;

			when WCW =>
				if readyMEM = '0' then
					nextstate <= WCW;
				elsif readyMEM = '1' then
					nextstate <= WRITE;
				end if;
				
				
			when WRITE => 
				nextstate <= IDLE;
				
				
				
				

			when CR =>
				if cacheHit = '1' then
					nextstate <= IDLE;
				elsif cacheHit = '0' then
					nextstate <= CMR;
				end if;

			when CMR =>
				if isDirty = '1' then
					nextstate <= WBR;
				elsif isDirty = '0' then
					nextstate <= WCR;
				end if;

			when WBR =>
				if readyMEM = '0' then
					nextstate <= WBR;
				elsif readyMEM = '1' then
					nextstate <= WCR;
				end if;

			when WCR =>
				if readyMEM = '0' then
					nextstate <= WCR;
				elsif readyMEM = '1' then
					nextstate <= IDLE;
				end if;

			when others => nextstate <= IDLE;
		end case;
	end process;

	
	wrCacheBlockLine <= '1' when (state=WCW and readyMEM='1') else
						'0' when (state=IDLE);

	rd <= '0' when (state=WCW and readyMEM='1');


	-- Output logic.
	wr        <= '0' when (state=WCW and readyMEM='1') else
				 '1' when (cacheHit = '1' and state = CW);

	stallCPU <= '1' when (cacheHit = '0' and state = CW) else '1' when (cacheHit = '0' and state = CR) else '0';

	wrMEM <= '1' when (isDirty = '1' and state = CMW) else 
		     '1' when (isDirty = '1' and state = CMR) else 
		     '0';

	rdMEM <= '1' when (state=CW and cacheHit='0' and valid='0') else
			 '1' when (isDirty = '1' and state = CMW) else 
			 '1' when (readyMEM = '1' and state = WBW) else 
			 '1' when (readyMEM = '1' and state = CMW) else 
			 '1' when (isDirty = '0' and state = CMR) else 
			 '1' when (readyMEM = '1' and state = WBR) else 
			 '1' when (readyMEM = '1' and state = WCR) else 
			 '0';

	setDirty <= '1' when (state = WRITE) else '0' when (state = IDLE);
 
 
 
	dataCPU_out <= directMappedCache_data_out when (cacheHit = '1' and state = CR);
	
	

end synth;
