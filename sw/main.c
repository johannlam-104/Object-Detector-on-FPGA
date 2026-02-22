// main.c - Zynq-7000 Standalone: staged VDMA bring-up
//
// Assumptions:
//  - 640x480, 32-bit pixels, stride = 2560 bytes
//  - VDMA base at XPAR_AXI_VDMA_0_BASEADDR
//  - DDR buffer at 0x0100_0000 (adjust if needed)
//
// Build: standalone domain

#include "xparameters.h"
#include "xaxivdma.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "sleep.h"
#include <string.h>

#define WIDTH  640
#define HEIGHT 480
#define BPP    4
#define HSIZE_BYTES   (WIDTH * BPP)     // 2560 (0xA00)
#define STRIDE_BYTES  (WIDTH * BPP)     // 2560 (0xA00)
#define FRAME_BYTES   (STRIDE_BYTES * HEIGHT)

#define VDMA_BASE   XPAR_AXI_VDMA_0_BASEADDR

// S2MM register offsets
#define S2MM_DMACR  (VDMA_BASE + 0x0030)
#define S2MM_DMASR  (VDMA_BASE + 0x0034)
#define S2MM_VSIZE  (VDMA_BASE + 0x00A0)
#define S2MM_HSIZE  (VDMA_BASE + 0x00A4)
#define S2MM_STRD   (VDMA_BASE + 0x00A8)
#define S2MM_ADDR0  (VDMA_BASE + 0x00AC)

// MM2S register offsets
#define MM2S_DMACR  (VDMA_BASE + 0x0000)
#define MM2S_DMASR  (VDMA_BASE + 0x0004)
#define MM2S_VSIZE  (VDMA_BASE + 0x0050)
#define MM2S_HSIZE  (VDMA_BASE + 0x0054)
#define MM2S_STRD   (VDMA_BASE + 0x0058)
#define MM2S_ADDR0  (VDMA_BASE + 0x005C)

#define FB_ADDR ((UINTPTR)0x01000000U)

#ifndef XPAR_AXI_VDMA_NUM_INSTANCES
#define XPAR_AXI_VDMA_NUM_INSTANCES 1
#endif
extern XAxiVdma_Config XAxiVdma_ConfigTable[XPAR_AXI_VDMA_NUM_INSTANCES];

static XAxiVdma_Config* VdmaLookupByBase(UINTPTR base_addr)
{
    for (int i = 0; i < (int)XPAR_AXI_VDMA_NUM_INSTANCES; i++) {
        if ((UINTPTR)XAxiVdma_ConfigTable[i].BaseAddress == base_addr) {
            return &XAxiVdma_ConfigTable[i];
        }
    }
    return NULL;
}

static void dump_chan(const char* tag,
                      UINTPTR dmacr, UINTPTR dmasr,
                      UINTPTR vsize, UINTPTR hsize,
                      UINTPTR strd,  UINTPTR addr0)
{
    u32 cr = Xil_In32(dmacr);
    u32 sr = Xil_In32(dmasr);

    xil_printf("%s_DMACR=0x%08x (RS=%d)\r\n", tag, cr, (cr & 1));
    xil_printf("%s_DMASR=0x%08x HALTED=%d IDLE=%d INTERR=%d SLVERR=%d DECERR=%d\r\n",
               tag, sr, (sr>>0)&1, (sr>>1)&1, (sr>>4)&1, (sr>>5)&1, (sr>>6)&1);

    xil_printf("%s_VSIZE=0x%08x HSIZE=0x%08x STRD=0x%08x ADDR0=0x%08x\r\n",
               tag,
               Xil_In32(vsize),
               Xil_In32(hsize),
               Xil_In32(strd),
               Xil_In32(addr0));
}

static void ddr_peek(UINTPTR base)
{
    volatile u32 *p = (volatile u32*)base;
    xil_printf("DDR peek @0x%08x: %08x %08x %08x %08x\r\n",
               (u32)base, p[0], p[1], p[2], p[3]);
}

int main(void)
{
    xil_printf("\r\n--- VDMA staged start (S2MM then MM2S), no SetFrmStore(READ) ---\r\n");
    xil_printf("VDMA_BASE=0x%08x  FB_ADDR=0x%08x  FRAME_BYTES=0x%08x\r\n",
               (u32)VDMA_BASE, (u32)FB_ADDR, (u32)FRAME_BYTES);

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

    // Clear latched status bits (W1C)
    Xil_Out32(S2MM_DMASR, 0xFFFFFFFF);
    Xil_Out32(MM2S_DMASR, 0xFFFFFFFF);

    xil_printf("Initial regs:\r\n");
    dump_chan("S2MM", S2MM_DMACR, S2MM_DMASR, S2MM_VSIZE, S2MM_HSIZE, S2MM_STRD, S2MM_ADDR0);
    dump_chan("MM2S", MM2S_DMACR, MM2S_DMASR, MM2S_VSIZE, MM2S_HSIZE, MM2S_STRD, MM2S_ADDR0);

    // ---------------- S2MM (WRITE) ----------------
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
    wr.FixedFrameStoreAddr = 0;   // park at frame 0 (single buffer)

    st = XAxiVdma_DmaConfig(&vdma, XAXIVDMA_WRITE, &wr);
    xil_printf("DmaConfig(WRITE)=%d\r\n", st);

    st = XAxiVdma_SetFrmStore(&vdma, 1, XAXIVDMA_WRITE);
    xil_printf("SetFrmStore(WRITE)=%d\r\n", st);

    UINTPTR addrs[1] = { FB_ADDR };
    st = XAxiVdma_DmaSetBufferAddr(&vdma, XAXIVDMA_WRITE, addrs);
    xil_printf("SetBufferAddr(WRITE)=%d\r\n", st);

    xil_printf("Starting S2MM...\r\n");
    st = XAxiVdma_DmaStart(&vdma, XAXIVDMA_WRITE);
    xil_printf("DmaStart(WRITE)=%d\r\n", st);

    usleep(20000);
    xil_printf("After S2MM start:\r\n");
    dump_chan("S2MM", S2MM_DMACR, S2MM_DMASR, S2MM_VSIZE, S2MM_HSIZE, S2MM_STRD, S2MM_ADDR0);

    // ---------------- MM2S (READ) ----------------
    // Clear any stale MM2S status again right before configuring/starting.
    Xil_Out32(MM2S_DMASR, 0xFFFFFFFF);

    XAxiVdma_DmaSetup rd;
    memset(&rd, 0, sizeof(rd));
    rd.VertSizeInput       = HEIGHT;
    rd.HoriSizeInput       = HSIZE_BYTES;
    rd.Stride              = STRIDE_BYTES;
    rd.FrameDelay          = 0;
    rd.EnableCircularBuf   = 1;
    rd.EnableSync          = 0;
    rd.PointNum            = 0;
    rd.EnableFrameCounter  = 0;
    rd.FixedFrameStoreAddr = 0;   // park at frame 0 (single buffer)

    st = XAxiVdma_DmaConfig(&vdma, XAXIVDMA_READ, &rd);
    xil_printf("DmaConfig(READ)=%d\r\n", st);


    st = XAxiVdma_DmaSetBufferAddr(&vdma, XAXIVDMA_READ, addrs);
    xil_printf("SetBufferAddr(READ)=%d\r\n", st);

    xil_printf("Starting MM2S...\r\n");
    st = XAxiVdma_DmaStart(&vdma, XAXIVDMA_READ);
    xil_printf("DmaStart(READ)=%d\r\n", st);

    Xil_Out32(MM2S_DMACR, Xil_In32(MM2S_DMACR) | 0x00000001U);

    usleep(20000);
    xil_printf("After MM2S start:\r\n");
    dump_chan("MM2S", MM2S_DMACR, MM2S_DMASR, MM2S_VSIZE, MM2S_HSIZE, MM2S_STRD, MM2S_ADDR0);

    // ---------------- Periodic monitor ----------------
    while (1) {
        usleep(20000000);
        dump_chan("S2MM", S2MM_DMACR, S2MM_DMASR, S2MM_VSIZE, S2MM_HSIZE, S2MM_STRD, S2MM_ADDR0);
        dump_chan("MM2S", MM2S_DMACR, MM2S_DMASR, MM2S_VSIZE, MM2S_HSIZE, MM2S_STRD, MM2S_ADDR0);
        ddr_peek(FB_ADDR);
    }
}
