// Applies re/rtl/rtl_names.csv names/signatures/comments to the current program.
// Idempotent: re-running with the same CSV yields the same names.
//@category Analysis
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

public class ApplyRtlNames extends GhidraScript {
    @Override
    public void run() throws Exception {
        String csvPath;
        if (getScriptArgs().length > 0) {
            csvPath = getScriptArgs()[0];
        } else {
            // default relative to project cwd expectation
            csvPath = "re/rtl/rtl_names.csv";
        }
        Path path = Paths.get(csvPath);
        if (!Files.exists(path)) {
            printerr("CSV not found: " + path.toAbsolutePath());
            return;
        }
        AddressFactory af = currentProgram.getAddressFactory();
        FunctionManager fm = currentProgram.getFunctionManager();
        int renamed = 0, commented = 0, skipped = 0;
        List<String> lines = Files.readAllLines(path, StandardCharsets.UTF_8);
        for (int i = 0; i < lines.size(); i++) {
            String line = lines.get(i).trim();
            if (line.isEmpty() || line.startsWith("address;") || line.startsWith("address,"))
                continue;
            // address;name;signature;unit;evidence;verified
            String[] parts = splitSemi(line);
            if (parts.length < 2) {
                skipped++;
                continue;
            }
            String addrStr = parts[0].trim();
            String name = parts[1].trim();
            String signature = parts.length > 2 ? parts[2].trim() : "";
            String unit = parts.length > 3 ? parts[3].trim() : "";
            String evidence = parts.length > 4 ? parts[4].trim() : "";
            String verified = parts.length > 5 ? parts[5].trim() : "";

            Address addr = parseAddr(af, addrStr);
            if (addr == null) {
                printerr("bad addr: " + addrStr);
                skipped++;
                continue;
            }
            Function fn = fm.getFunctionAt(addr);
            if (fn == null) {
                // create even without TP prologue (thin FAR wrappers)
                try {
                    disassemble(addr);
                } catch (Exception e) {
                    /* ignore */
                }
                fn = createFunction(addr, name);
            }
            if (fn == null) {
                // last resort: createSymbol only
                try {
                    currentProgram.getSymbolTable()
                        .createLabel(addr, name, SourceType.USER_DEFINED);
                    String comment = "RTL " + unit + " [" + verified + "]: " + evidence;
                    if (signature != null && !signature.isEmpty()) {
                        comment = signature + " | " + comment;
                    }
                    currentProgram.getListing().setComment(addr, CodeUnit.PLATE_COMMENT, comment);
                    commented++;
                    renamed++;
                    continue;
                } catch (Exception e) {
                    printerr("no function at " + addrStr);
                    skipped++;
                    continue;
                }
            }
            if (!name.equals(fn.getName())) {
                fn.setName(name, SourceType.USER_DEFINED);
                renamed++;
            } else {
                // already named — still count as applied
                renamed++;
            }
            String comment = "RTL " + unit + " [" + verified + "]: " + evidence;
            if (signature != null && !signature.isEmpty()) {
                comment = signature + " | " + comment;
            }
            currentProgram.getListing().setComment(addr, CodeUnit.PLATE_COMMENT, comment);
            commented++;
        }
        println("ApplyRtlNames: renamed/kept=" + renamed + " commented=" + commented + " skipped=" + skipped);
    }

    private static String[] splitSemi(String line) {
        // simple split on ';' — evidence field may contain commas but not semicolons in our CSV
        List<String> out = new ArrayList<>();
        StringBuilder cur = new StringBuilder();
        for (int i = 0; i < line.length(); i++) {
            char c = line.charAt(i);
            if (c == ';') {
                out.add(cur.toString());
                cur.setLength(0);
            } else {
                cur.append(c);
            }
        }
        out.add(cur.toString());
        return out.toArray(new String[0]);
    }

    private Address parseAddr(AddressFactory af, String s) {
        // "1c5b:112b" or "1827:1dc2"
        try {
            if (s.contains(":")) {
                String[] p = s.split(":");
                int seg = Integer.parseInt(p[0], 16);
                int off = Integer.parseInt(p[1], 16);
                long linear = ((long) seg << 4) + off;
                // Ghidra segmented space: try seg:off default space
                AddressSpace space = af.getDefaultAddressSpace();
                // Prefer segmented form if available
                try {
                    return af.getAddress(String.format("%04X:%04X", seg, off));
                } catch (Exception e) {
                    return space.getAddress(linear);
                }
            }
            return af.getAddress(s);
        } catch (Exception e) {
            return null;
        }
    }
}
