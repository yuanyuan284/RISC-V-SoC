"""Generate functional BRAM models from the installed vendor port definitions.

These models verify bus logic and memory contents, not silicon timing. The
vendor's encrypted primitives require a supported commercial simulator.
"""
from pathlib import Path
import re
import os

ROOT = Path(__file__).resolve().parents[1]
ARCH = Path(os.environ.get('EF2_MACRO_SOURCE', r'D:\TD_5.6.5_Release_119.222\arch\ef2_macro.v'))

def main():
    (ROOT / 'build/stage3').mkdir(parents=True, exist_ok=True)
    text = ARCH.read_text()
    result = ['`timescale 1ns/1ps\n']
    for name, width, depth in [('EF2_PHY_BRAM32K',16,2048),
                               ('EF2_PHY_BRAM128K',32,4096),
                               ('EF2_PHY_BRAM256K',32,8192)]:
        block = re.search(r'module '+name+r'\s*\(.*?endmodule', text, re.S).group()
        header = block[:block.index(');')+2]
        declarations = re.findall(r'^\s*(?:input|output|parameter)\s+[^;]+;', block, re.M)
        result += [header+'\n', '\n'.join(declarations)+'\n',
                   f'reg [{width-1}:0] memory [0:{depth-1}];\ninteger i;\n']
        init_names = re.findall(r'parameter (INIT_[0-9A-F]+)\s*=', block)
        result += ['initial begin\n']
        for group, param in enumerate(init_names):
            for j in range(256 // width):
                result += [f'memory[{group * (256//width)+j}] = {param}[{width*j} +: {width}];\n']
        result += ['end\n']
        if width == 16:
            result += ["reg [15:0] out; assign doa = out; assign dob = 0;\n",
                "always @(posedge clka) if(csa) begin\n",
                "if(wea) begin\n",
                "if(!bytewea || !bytea) memory[addra][7:0] <= dia[7:0];\n",
                "if(!bytewea || bytea) memory[addra][15:8] <= dia[15:8];\n",
                "end else out <= memory[addra]; end\n"]
        else:
            if depth == 4096:
                clock, ce, we, mask, addr, data, output = 'clk','ce','we','webyte','addr','di','do'
            else:
                clock, ce, we, mask, addr, data, output = 'clka','cea','wea','weabyte','addra','dia','doa'
                result += ['assign dob = 0;\n']
            result += [f'reg [31:0] out; assign {output} = out;\n',
                f'always @(posedge {clock}) if({ce}) begin\n',
                f'if({we}) begin\n']
            for lane in range(4):
                result += [f'if({mask}[{lane}]) memory[{addr}][{lane*8} +: 8] <= {data}[{lane*8} +: 8];\n']
            result += [f'end else out <= memory[{addr}]; end\n']
        result += ['endmodule\n']
    # The vendor's port named "do" is a SystemVerilog keyword.
    model = re.sub(r'\bdo\b', lambda _: '\\do ', ''.join(result))
    (ROOT/'build/stage3/bram_functional_models.v').write_text(model, encoding='ascii')
    memory = (ROOT/'rtl/stage3/stage3_memory.v').read_text()
    memory = memory.replace('.do(', '.\\do (')
    (ROOT/'build/stage3/stage3_memory_sim.v').write_text(memory, encoding='ascii')

if __name__ == '__main__':
    main()
