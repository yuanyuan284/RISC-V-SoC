package soc

import spinal.core._
import spinal.lib._
import spinal.lib.cpu.riscv.debug.DebugTransportModuleParameter
import vexriscv.{VexRiscv, VexRiscvConfig, plugin}
import vexriscv.ip.InstructionCacheConfig
import vexriscv.plugin._

object GenDebugCpu extends App {
  val output = if (args.nonEmpty) args(0) else "build/cpu-debug"
  SpinalConfig(targetDirectory = output, inlineRom = true).generateVerilog {
    val config = VexRiscvConfig(plugins = List(
      new IBusCachedPlugin(
        resetVector = null,
        prediction = STATIC,
        memoryTranslatorPortConfig = (),
        config = InstructionCacheConfig(
          cacheSize = 4096, bytePerLine = 32, wayCount = 1,
          addressWidth = 32, cpuDataWidth = 32, memDataWidth = 32,
          catchIllegalAccess = true, catchAccessFault = true,
          asyncTagMemory = false, twoCycleRam = true
        )
      ),
      new StaticMemoryTranslatorPlugin(address => address(31 downto 28) === 4),
      new DBusSimplePlugin(catchAddressMisaligned = true, catchAccessFault = true),
      new DecoderSimplePlugin(catchIllegalInstruction = true),
      new RegFilePlugin(regFileReadyKind = plugin.SYNC, zeroBoot = true),
      new IntAluPlugin,
      new SrcPlugin(separatedAddSub = false, executeInsertion = true),
      new LightShifterPlugin,
      new MulDivIterativePlugin(genMul = true, genDiv = true,
        mulUnrollFactor = 1, divUnrollFactor = 1),
      new HazardSimplePlugin(
        bypassExecute = true, bypassMemory = true, bypassWriteBack = true,
        bypassWriteBackBuffer = true, pessimisticUseSrc = false,
        pessimisticWriteRegFile = false, pessimisticAddressMatch = false
      ),
      new BranchPlugin(earlyBranch = false, catchAddressMisaligned = true),
      new CsrPlugin(CsrPluginConfig.small(0x20000000L).copy(
        withPrivilegedDebug = true, debugTriggers = 2,
        misaAccess = CsrAccess.READ_ONLY, misaExtensionsInit = 0x1100,
        mhartid = 0, ebreakGen = true
      )),
      new EmbeddedRiscvJtag(
        p = DebugTransportModuleParameter(addressWidth = 7, version = 1, idle = 7),
        debugCd = ClockDomain.current.copy(reset = Bool().setName("debugReset")),
        withTap = true, withTunneling = false
      )
    ))
    val cpu = new VexRiscv(config)
    cpu.setDefinitionName("VexRiscvDebug")
    cpu.rework {
      config.plugins.foreach {
        case p: IBusCachedPlugin =>
          p.iBus.setAsDirectionLess()
          master(p.iBus.toWishbone()).setName("iBusWishbone")
        case p: DBusSimplePlugin =>
          p.dBus.setAsDirectionLess()
          master(p.dBus.toWishbone()).setName("dBusWishbone")
        case _ =>
      }
    }
    cpu
  }
}
