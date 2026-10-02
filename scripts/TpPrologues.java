// Создаёт функции по прологу Turbo Pascal: 55 89 E5 (push bp; mov bp,sp).
//@category Analysis
import ghidra.app.script.GhidraScript;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.program.model.address.*;
import ghidra.program.model.mem.*;

public class TpPrologues extends GhidraScript {
    @Override
    public void run() throws Exception {
        Memory mem = currentProgram.getMemory();
        byte[] pat = {0x55, (byte) 0x89, (byte) 0xE5};
        int n = 0;
        for (MemoryBlock b : mem.getBlocks()) {
            if (!b.isInitialized() || !b.isExecute()) continue;
            Address a = b.getStart();
            while (a != null && a.compareTo(b.getEnd()) <= 0) {
                Address hit = mem.findBytes(a, b.getEnd(), pat, null, true, monitor);
                if (hit == null) break;
                if (getFunctionAt(hit) == null) {
                    new DisassembleCommand(hit, null, true).applyTo(currentProgram, monitor);
                    new CreateFunctionCmd(hit).applyTo(currentProgram, monitor);
                    n++;
                }
                a = hit.add(1);
            }
        }
        println("TpPrologues: created " + n);
    }
}
