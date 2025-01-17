@echo off
REM you have to specify the assembler text for the mips at the prompt!

IF "%~1"=="" (
echo usage: run_ghdl.bat path/asm-file-without-extension
GOTO :eof
)

REM Remove the work directory if it already exists.
echo ++++++++++ Create work folder +++++++++++++++++++++++++++++++++
if exist workB ( 
	echo "Remove work directory."
	rmdir /s /q .\workB
) 

REM Create new work folder if it does not exist.
if not exist workB (
	echo "Create work directory."
	mkdir "workB"
 )
 
echo ++++++++++ assemble the MIPS program (imem and dmem) ++++++++++
java -jar ./../../../Mars4_5.jar a dump .text HexText ../imem/%1.imem ../asm/%1.asm
java -jar ./../../../Mars4_5.jar a dump .data HexText ../dmem/%1.dmem ../asm/%1.asm
echo.
echo ++++++++++ check syntax of the vhdl file gates.vhd ++++++++++
ghdl -a -g -O3 --ieee=synopsys --workdir=workB convertMemFiles.vhd
echo.
echo ++++++++++ create an executable for the testbench ++++++++++
ghdl -e -g -O3 --ieee=synopsys --workdir=workB convertMemFiles
echo.
echo ++++++++++ run the executable ++++++++++
ghdl -r -g -O3 --ieee=synopsys --workdir=workB convertMemFiles -gDFileName="../dmem/%1" -gIFileName="../imem/%1"
echo.
echo ++++++++++ Create files for cache BRAMs +++++++++++++++++++++++
echo.
ghdl -a -g -O3 --ieee=synopsys --workdir=workB cache_pkg.vhd creatorOfCacheFiles.vhd
echo.
echo ++++++++++ create an executable for the testbench ++++++++++
ghdl -e -g -O3 --ieee=synopsys --workdir=workB creatorOfCacheFiles
echo.
echo ++++++++++ run the executable ++++++++++
ghdl -r -g -O3 --ieee=synopsys --workdir=workB creatorOfCacheFiles -gTag_Filename="../imem/tag%1" -gData_Filename="../imem/data%1" -gFILE_EXTENSION=".imem"

@echo off
echo.
echo ++++++++++ add files in the work design library ++++++++++
ghdl -i -g -O3 --ieee=synopsys --workdir=workB mips_pkg.vhd casts.vhd cache_pkg.vhd bram.vhd directMappedCacheController.vhd mainMemoryController.vhd mainMemory.vhd directMappedCache.vhd cacheController.vhd cache.vhd cache_tb.vhd 
echo.
echo ++++++++++ analyze automatically outdated files and create an executable ++++++++++
ghdl -m -g -O3 --ieee=synopsys --workdir=workB cache_tb
echo.
echo ++++++++++ run the executable for 15us and save all waveforms ++++++++++
ghdl -r -g -O3 --ieee=synopsys --workdir=workB cache_tb --stop-time=300000ns  --wave=../sim/cacheTestbench.ghw -gMAIN_MEMORY_FILENAME="../imem/%1" -gData_Filename="../imem/data%1" -gTag_Filename="../imem/tag%1" -gFILE_EXTENSION=".imem"
