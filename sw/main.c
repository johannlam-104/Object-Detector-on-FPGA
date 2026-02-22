// main.c - Zynq-7000 Standalone: Triple-buffer VDMA bring-up (no SG)
//
// Assumptions:
//  - 640x480
//  - 32-bit pixels on AXIS (1 pixel/beat), stride = 2560 bytes
//  - VDMA base at XPAR_AXI_VDMA_0_BASEADDR
//  - DDR buffers at FB0..FB2 (adjust if needed)

#include "xparameters.h"
#include "xaxivdma.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "sleep.h"
#include <string.h>

#define WIDTH  640
#define HEIGHT 480
#define BPP    4
#define HSIZE_BYTES   (WIDTH * BPP)             // 2560
#define STRIDE_BYTES  (WIDTH * BPP)             // 2560
#define FRAME_BYTES   (STRIDE_BYTES * HEIGHT)   // 1,228,800 = 0x0012C000

#define VDMA_BASE   XPAR_AXI_VDMA_0_BASEADDR

// 3 contiguous framebuffers in DDR (must not overlap program/heap/stack)
#define FB0_ADDR ((UINTPTR)0x01000000U)
#define FB1_ADDR ((UINTPTR)(FB0_ADDR + FRAME_BYTES))
#define FB2_ADDR ((UINTPTR)(FB1_ADDR + FRAME_BYTES))

// Register offsets (AXI VDMA)
#define MM2S_DMACR      (VDMA_BASE + 0x0000)
#define MM2S_DMASR      (VDMA_BASE + 0x0004)
#define MM2S_FRMDLY_STR (VDMA_BASE + 0x0018)
#define MM2S_HSIZE      (VDMA_BASE + 0x001C)
#define MM2S_VSIZE      (VDMA_BASE + 0x0000 + 0x0050) // 0x0050
#define MM2S_STRD       (VDMA_BASE + 0x0058)
#define MM2S_ADDR0      (VDMA_BASE + 0x005C)
#define MM2S_ADDR1      (VDMA_BASE + 0x0060)
#define MM2S_ADDR2      (VDMA_BASE + 0x0064)
// (More addresses exist, but you only need 0..2 for triple buffering)

#define S2MM_DMACR      (VDMA_BASE + 0x0030)
#define S2MM_DMASR      (VDMA_BASE + 0x0034)
#define S2MM_VSIZE      (VDMA_BASE + 0x00A0)
#define S2MM_HSIZE      (VDMA_BASE + 0x00A4)
#define S2MM_STRD       (VDMA_BASE + 0x00A8)
#define S2MM_ADDR0      (VDMA_BASE + 0x00AC)
#define S2MM_ADDR1      (VDMA_BASE + 0x00B0)
#define S2MM_ADDR2      (VDMA_BASE + 0x00B4)

#define DMACR_RS        0x00000001U
#define DMACR_RESET     0x00000004U

#ifndef XPAR_XAXIVDMA_NUM_INSTANCES
#define XPAR_XAXIVDMA_NUM_INSTANCES 1
#endif
extern XAxiVdma_Config XAxiVdma_ConfigTable[XPAR_XAXIVDMA_NUM_INSTANCES];

static XAxiVdma_Config* VdmaLookupByBase(UINTPTR base_addr)
{
    for (int i = 0; i < (int)XPAR_XAXIVDMA_NUM_INSTANCES; i++) {
        if ((UINTPTR)XAxiVdma_ConfigTable[i].BaseAddress == base_addr) {
            return &XAxiVdma_ConfigTable[i];
        }
    }
    return NULL;
}

static void dump_chan(const char* tag, UINTPTR dmacr, UINTPTR dmasr)
{
    u32 cr = Xil_In32(dmacr);
    u32 sr = Xil_In32(dmasr);

    xil_printf("%s_DMACR=0x%08x (RS=%d RESET=%d)\r\n",
               tag, cr,
               (cr & DMACR_RS) ? 1 : 0,
               (cr & DMACR_RESET) ? 1 : 0);

    xil_printf("%s_DMASR=0x%08x HALTED=%d IDLE=%d INTERR=%d SLVERR=%d DECERR=%d\r\n",
               tag, sr,
               (sr >> 0) & 1,
               (sr >> 1) & 1,
               (sr >> 4) & 1,
               (sr >> 5) & 1,
               (sr >> 6) & 1);
}

static void dump_addrs(void)
{
    xil_printf("MM2S_ADDR0=0x%08x ADDR1=0x%08x ADDR2=0x%08x\r\n",
               Xil_In32(MM2S_ADDR0), Xil_In32(MM2S_ADDR1), Xil_In32(MM2S_ADDR2));
    xil_printf("S2MM_ADDR0=0x%08x ADDR1=0x%08x ADDR2=0x%08x\r\n",
               Xil_In32(S2MM_ADDR0), Xil_In32(S2MM_ADDR1), Xil_In32(S2MM_ADDR2));
}

static int chan_reset(UINTPTR dmacr, UINTPTR dmasr)
{
    // Stop channel (RS=0)
    Xil_Out32(dmacr, Xil_In32(dmacr) & ~DMACR_RS);

    // Assert reset
    Xil_Out32(dmacr, Xil_In32(dmacr) | DMACR_RESET);

    // Wait for reset to self-clear
    for (int i = 0; i < 1000000; i++) {
        if ((Xil_In32(dmacr) & DMACR_RESET) == 0) break;
    }
    if (Xil_In32(dmacr) & DMACR_RESET) return XST_FAILURE;

    // Clear latched status (W1C)
    Xil_Out32(dmasr, 0xFFFFFFFF);

    return XST_SUCCESS;
}

int main(void)
{
    xil_printf("\r\n--- VDMA triple-buffer start (3 frame stores), READ SetFrmStore bypass ---\r\n");
    xil_printf("VDMA_BASE=0x%08x\r\n", (u32)VDMA_BASE);
    xil_printf("FB0=0x%08x FB1=0x%08x FB2=0x%08x FRAME_BYTES=0x%08x\r\n",
               (u32)FB0_ADDR, (u32)FB1_ADDR, (u32)FB2_ADDR, (u32)FRAME_BYTES);

    XAxiVdma vdma;
    XAxiVdma_Config *cfg = VdmaLookupByBase((UINTPTR)VDMA_BASE);
    if (!cfg) {
        xil_printf("ERROR: VDMA config not found for base addr.\r\n");
        while (1) { usleep(500000); }
    }

    int st = XAxiVdma_CfgInitialize(&vdma, cfg, cfg->BaseAddress);
    if (st != XST_SUCCESS) {
        xil_printf("ERROR: CfgInitialize failed (%d)\r\n", st);
        while (1) { usleep(500000); }
    }

    xil_printf("Resetting S2MM...\r\n");
    if (chan_reset(S2MM_DMACR, S2MM_DMASR) != XST_SUCCESS) {
        xil_printf("ERROR: S2MM reset timeout\r\n");
        while (1) {}
    }

    xil_printf("Resetting MM2S...\r\n");
    if (chan_reset(MM2S_DMACR, MM2S_DMASR) != XST_SUCCESS) {
        xil_printf("ERROR: MM2S reset timeout\r\n");
        while (1) {}
    }

    xil_printf("After resets:\r\n");
    dump_chan("S2MM", S2MM_DMACR, S2MM_DMASR);
    dump_chan("MM2S", MM2S_DMACR, MM2S_DMASR);

    UINTPTR addrs[3] = { FB0_ADDR, FB1_ADDR, FB2_ADDR };

    // ---------------- S2MM (WRITE) via driver ----------------
    XAxiVdma_DmaSetup wr;
    memset(&wr, 0, sizeof(wr));
    wr.VertSizeInput       = HEIGHT;
    wr.HoriSizeInput       = HSIZE_BYTES;
    wr.Stride              = STRIDE_BYTES;
    wr.FrameDelay          = 0;
    wr.EnableCircularBuf   = 1;
    wr.EnableSync          = 0;    
    wr.PointNum            = 0;
    wr.EnableFrameCounter  = 0;
    wr.FixedFrameStoreAddr = 0;

    st = XAxiVdma_DmaConfig(&vdma, XAXIVDMA_WRITE, &wr);
    xil_printf("DmaConfig(WRITE)=%d\r\n", st);
    if (st != XST_SUCCESS) while (1) {}

    st = XAxiVdma_SetFrmStore(&vdma, 3, XAXIVDMA_WRITE);
    xil_printf("SetFrmStore(WRITE,3)=%d\r\n", st);
    if (st != XST_SUCCESS) while (1) {}

    st = XAxiVdma_DmaSetBufferAddr(&vdma, XAXIVDMA_WRITE, addrs);
    xil_printf("SetBufferAddr(WRITE,3)=%d\r\n", st);
    if (st != XST_SUCCESS) while (1) {}

    // Also program S2MM address regs directly (helps debug; should match driver)
    Xil_Out32(S2MM_ADDR0, (u32)FB0_ADDR);
    Xil_Out32(S2MM_ADDR1, (u32)FB1_ADDR);
    Xil_Out32(S2MM_ADDR2, (u32)FB2_ADDR);

    xil_printf("Starting S2MM...\r\n");
    st = XAxiVdma_DmaStart(&vdma, XAXIVDMA_WRITE);
    xil_printf("DmaStart(WRITE)=%d\r\n", st);
    if (st != XST_SUCCESS) while (1) {}

    usleep(20000);
    dump_chan("S2MM", S2MM_DMACR, S2MM_DMASR);

    // ---------------- MM2S (READ) via driver, but NO SetFrmStore(READ) ----------------
    // Reset MM2S again right before READ config
    xil_printf("Resetting MM2S again before READ config...\r\n");
    if (chan_reset(MM2S_DMACR, MM2S_DMASR) != XST_SUCCESS) {
        xil_printf("ERROR: MM2S reset timeout (pre-READ)\r\n");
        while (1) {}
    }

    XAxiVdma_DmaSetup rd;
    memset(&rd, 0, sizeof(rd));
    rd.VertSizeInput       = HEIGHT;
    rd.HoriSizeInput       = HSIZE_BYTES;
    rd.Stride              = STRIDE_BYTES;
    rd.FrameDelay          = 0;
    rd.EnableCircularBuf   = 0;
    rd.EnableSync          = 0;    
    rd.PointNum            = 0;
    rd.EnableFrameCounter  = 0;
    rd.FixedFrameStoreAddr = 0;

    st = XAxiVdma_DmaConfig(&vdma, XAXIVDMA_READ, &rd);
    xil_printf("DmaConfig(READ)=%d\r\n", st);
    if (st != XST_SUCCESS) while (1) {}

    Xil_Out32(MM2S_ADDR0, (u32)FB0_ADDR);
    Xil_Out32(MM2S_ADDR1, (u32)FB1_ADDR);
    Xil_Out32(MM2S_ADDR2, (u32)FB2_ADDR);

    st = XAxiVdma_DmaSetBufferAddr(&vdma, XAXIVDMA_READ, addrs);
    xil_printf("SetBufferAddr(READ,3)=%d\r\n", st);

    xil_printf("Addresses after programming:\r\n");
    dump_addrs();

    xil_printf("Starting MM2S...\r\n");
    st = XAxiVdma_DmaStart(&vdma, XAXIVDMA_READ);
    xil_printf("DmaStart(READ)=%d\r\n", st);
    if (st != XST_SUCCESS) while (1) {}

    // Force RS just in case
    Xil_Out32(MM2S_DMACR, Xil_In32(MM2S_DMACR) | DMACR_RS);

    usleep(20000);
    dump_chan("MM2S", MM2S_DMACR, MM2S_DMASR);

    xil_printf("Running. Hardware steady-state.\r\n");

    while (1) {
        usleep(80000000);
        dump_chan("S2MM", S2MM_DMACR, S2MM_DMASR);
        dump_chan("MM2S", MM2S_DMACR, MM2S_DMASR);
    }
}
