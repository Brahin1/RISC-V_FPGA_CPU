"""RISCOF reference plugin: Spike, configured with the same memory map as the
large-memory simulation build of the core."""

import logging
import os

import riscof.utils as utils
from riscof.pluginTemplate import pluginTemplate

logger = logging.getLogger()


class spike_ref(pluginTemplate):
    __model__ = "spike"
    __version__ = "1.1.1"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        config = kwargs.get("config")
        if config is None:
            raise SystemExit("spike_ref: missing config")
        self.ref_exe = os.path.join(config.get("PATH", ""), "spike")
        self.num_jobs = str(config.get("jobs", 1))
        self.pluginpath = os.path.abspath(config["pluginpath"])

    def initialise(self, suite, work_dir, archtest_env):
        self.work_dir = work_dir
        self.suite_dir = suite
        self.compile_cmd = ("riscv64-unknown-elf-gcc -march={0} -mabi=ilp32 -static -mcmodel=medany "
                            "-fvisibility=hidden -nostdlib -nostartfiles -g "
                            f"-T {self.pluginpath}/env/link.ld -I {self.pluginpath}/env/ "
                            f"-I {archtest_env} {{1}} -o {{2}} {{3}}")

    def build(self, isa_yaml, platform_yaml):
        pass

    def runTests(self, testList, cgf_file=None):
        mk = os.path.join(self.work_dir, "Makefile." + self.name[:-1])
        if os.path.exists(mk):
            os.remove(mk)
        make = utils.makeUtil(makefilePath=mk)
        make.makeCommand = "make -k -j" + self.num_jobs

        for testname, t in testList.items():
            test_dir = t["work_dir"]
            sig = os.path.join(test_dir, self.name[:-1] + ".signature")
            macros = " -D" + " -D".join(t["macros"])
            march = t["isa"].lower()
            if "_zicsr" not in march:
                march = march.replace("zicsr", "_zicsr")
            build = self.compile_cmd.format(march, macros, "ref.elf", t["test_path"])
            run = (f"{self.ref_exe} --disable-dtb --no-dm --priv=m --isa=rv32im_zicsr "
                   f"-m0x0:0x200000,0x400000:0x10000,0x10000000:0x1000 "
                   f"+signature={sig} +signature-granularity=4 ref.elf")
            make.add_target(f"@cd {test_dir}; {build}; {run};")

        make.execute_all(self.work_dir)
