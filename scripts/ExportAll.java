// Выгружает список функций, строки и декомпиляцию всех функций в каталог из аргумента.
//@category Export
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.data.*;
import java.io.*;

public class ExportAll extends GhidraScript {
    @Override
    public void run() throws Exception {
        String outDir = getScriptArgs()[0];
        new File(outDir).mkdirs();
        DecompInterface di = new DecompInterface();
        di.openProgram(currentProgram);
        try (PrintWriter fl = new PrintWriter(outDir + "/functions.txt");
             PrintWriter dc = new PrintWriter(outDir + "/decomp.c")) {
            for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
                if (monitor.isCancelled()) break;
                long sz = f.getBody().getNumAddresses();
                fl.printf("%s\t%d\t%s\n", f.getEntryPoint(), sz, f.getName());
                DecompileResults r = di.decompileFunction(f, 60, monitor);
                dc.printf("// ==== %s %s (%d bytes)\n", f.getEntryPoint(), f.getName(), sz);
                if (r != null && r.decompileCompleted())
                    dc.println(r.getDecompiledFunction().getC());
                else
                    dc.println("// decompile failed");
            }
        }
        try (PrintWriter st = new PrintWriter(outDir + "/strings.txt")) {
            for (Data d : currentProgram.getListing().getDefinedData(true))
                if (d.hasStringValue()) st.printf("%s\t%s\n", d.getAddress(), d.getDefaultValueRepresentation());
        }
    }
}
