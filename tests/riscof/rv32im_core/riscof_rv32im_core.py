"""RISCOF DUT plugin: five-stage RV32IM core, Verilator model."""

import logging
import os

import riscof.utils as utils
from riscof.pluginTemplate import pluginTemplate

logger = logging.getLogger()

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


class rv32im_core(pluginTemplate):
    __model__ = "rv32im_core"
    __version__ = "1.0"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        config = kwargs.get("config")
        if config is None:
            raise SystemExit("rv32im_core: missing config")
        self.dut_exe = os.path.join(ROOT, "tb", "verilator", "obj_dir_riscof", "Vsoc_top")
        self.num_jobs = str(config.get("jobs", 1))
        self.pluginpath = os.path.abspath(config["pluginpath"])
        self.isa_spec = os.path.abspath(config["ispec"])
        self.platform_spec = os.path.abspath(config["pspec"])
        self.target_run = config.get("target_run", "1") != "0"

    def initialise(self, suite, work_dir, archtest_env):
        self.work_dir = work_dir
        self.suite_dir = suite
        self.compile_cmd = ("riscv64-unknown-elf-gcc -march={0} -mabi=ilp32 -static -mcmodel=medany "
                            "-fvisibility=hidden -nostdlib -nostartfiles -g "
                            f"-T {self.pluginpath}/env/link.ld -I {self.pluginpath}/env/ "
                            f"-I {archtest_env} {{1}} -o {{2}} {{3}}")

    def build(self, isa_yaml, platform_yaml):
        if not os.path.exists(self.dut_exe):
            raise SystemExit(f"build the simulator first: make -C tb/verilator riscof ({self.dut_exe})")

    def runTests(self, testList):
        mk = os.path.join(self.work_dir, "Makefile." + self.name[:-1])
        if os.path.exists(mk):
            os.remove(mk)
        make = utils.makeUtil(makefilePath=mk)
        make.makeCommand = "make -k -j" + self.num_jobs

        for testname, t in testList.items():
            test_dir = t["work_dir"]
            sig = os.path.join(test_dir, self.name[:-1] + ".signature")
            macros = " -D" + " -D".join(t["macros"])
            march = t["isa"].lower().replace("zicsr", "_zicsr") if "_zicsr" not in t["isa"].lower() \
                else t["isa"].lower()
            build = self.compile_cmd.format(march, macros, "my.elf", t["test_path"])
            hexes = (f"python3 {ROOT}/tools/elf2hex.py my.elf --out my --imem-size 0x200000 "
                     f"--dmem-base 0x400000 --dmem-size 0x10000")
            if self.target_run:
                run = (f"{self.dut_exe} +imem=my.imem.hex +dmem=my.dmem.hex +quiet "
                       f"+max_cycles=20000000 +signature={sig} "
                       f"+sig_begin=$$(riscv64-unknown-elf-nm my.elf | awk '/ begin_signature$$/{{print $$1}}') "
                       f"+sig_end=$$(riscv64-unknown-elf-nm my.elf | awk '/ end_signature$$/{{print $$1}}')")
            else:
                run = 'echo "NO RUN"'
            make.add_target(f"@cd {test_dir}; {build}; {hexes}; {run};")

        make.execute_all(self.work_dir)
        if not self.target_run:
            raise SystemExit(0)
