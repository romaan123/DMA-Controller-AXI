# DMA_Controller_AXI

## 1. Project Overview

This project implements a full **AXI4 Direct Memory Access (DMA) controller** along with a corresponding **AXI memory slave**. The design extends a simplified AXI-Lite-based approach to support high-throughput bulk data transfers using AXI4 `INCR` bursts.

The DMA operates with a **strictly in-order transaction model**, ensuring predictable and reliable transaction completion. An **APB interface** is provided for configuring the DMA, allowing the host to specify transfer addresses, length, and data width.

Supported transfer sizes are **8-bit, 16-bit, and 32-bit**.

## 2. System Architecture

The design consists of three main logical blocks connected through a **single-master, single-slave AXI interconnect**:

- **APB Configuration Interface:**  
  Serves as the control interface for the DMA. It provides zero-wait-state access to memory-mapped registers through which the host can configure the Source Address, Destination Address, Transfer Length, and Transfer Size (8-bit, 16-bit, or 32-bit). It also provides a Control register for Start/Stop control and a Status register containing Busy, Done, and Error indicators.

- **DMA Controller (AXI Master):**  
  Acts as the main data-movement engine. The controller contains a **16-word internal buffer** that temporarily stores data between AXI read and write operations. It automatically determines the appropriate burst length and ensures that no AXI transaction exceeds the supported **16-beat burst limit**. The DMA also performs dynamic byte-lane steering by generating `WSTRB` according to the configured transfer size and destination address alignment.

- **AXI Full Slave (Memory):**  
  Implements a byte-addressable SRAM with independent Read and Write FSMs. The slave handles AXI `VALID`/`READY` handshakes, maintains beat counters, generates `RLAST`, validates `WLAST`, and performs memory boundary checks. If a burst accesses an address outside the available memory range, the slave generates an AXI `SLVERR` response.

## 3. Finite State Machine (FSM) Analysis

### DMA Controller FSM

The DMA Master is controlled by a **7-state FSM** that provides strictly ordered transaction execution:

1. **IDLE:**  
   Waits for the APB `Start` command and initializes the required counters and control information.

2. **READ_ADDR:**  
   Generates the AXI read-address transaction using `ARADDR` and `ARLEN`. For transfers larger than 16 beats, the requested length is automatically divided into smaller bursts.

3. **READ_DATA:**  
   Receives the data from the AXI slave and stores each beat in the internal buffer. The controller monitors `RLAST` and checks `RRESP` for read errors.

4. **WRITE_ADDR:**  
   After the read burst has completed, the DMA issues the corresponding AXI write-address transaction. The write burst length matches the completed read burst.

5. **WRITE_DATA:**  
   Sends the buffered data to the AXI slave. The controller dynamically generates `WSTRB` based on the configured transfer size and destination address alignment. The burst completes when `WLAST` is asserted.

6. **WRITE_RESP:**  
   Waits for the AXI `BVALID` response handshake and checks `BRESP` for any write-side errors.

7. **UPDATE:**  
   Updates the remaining transfer count and increments the source and destination addresses. If additional data remains, the FSM returns to `READ_ADDR`. Once the entire transfer is complete, the DMA asserts the `Done` status and returns to `IDLE`.

### AXI Slave FSMs

The memory slave uses two independent FSMs for read and write operations. This separation helps maintain independent channel operation and prevents unnecessary dependencies between the two paths.

- **Write FSM:**  
  Moves from `IDLE` to `ACTIVE` after successfully accepting an `AWVALID` transaction. During the active state, incoming write data is stored in memory according to the `WSTRB` byte-enable signals. The FSM remains active until `WLAST` is received. It then verifies that the number of received beats matches the expected `AWLEN` and transitions to the response state, where it generates either an `OKAY` or `SLVERR` response.

- **Read FSM:**  
  Transitions from `IDLE` to `ACTIVE` after accepting an `ARVALID` transaction. It prepares the requested memory data and keeps track of the current beat. The beat counter is updated whenever an `RVALID`/`RREADY` handshake occurs. `RLAST` is asserted on the final beat according to the requested `ARLEN`.

## 4. Design Decisions & Transaction Ordering Analysis

### Strictly In-Order Execution

To meet the requirement for **strictly in-order transaction completion**, the DMA does not issue multiple outstanding AXI transactions. Instead, it follows a sequential:

**Read Burst → Buffer → Write Burst → B-Response**

execution model.

This approach significantly simplifies the controller by eliminating the need for multiple outstanding transaction management and complex AXI ID tracking. It also reduces the possibility of race conditions and provides deterministic behavior that is easier to verify.

### Dynamic Burst Slicing — 18-Beat Example

AXI4 `INCR` bursts are limited to a maximum of **16 beats**. Therefore, when the configured transfer length exceeds 16 beats, the DMA automatically divides the transfer into multiple bursts.

For example, an **18-beat transfer** is divided into two bursts:

- **First burst:** 16 beats
  - `ARLEN = 15`
  - `AWLEN = 15`

- **Second burst:** 2 beats
  - `ARLEN = 1`
  - `AWLEN = 1`

The DMA first completes the 16-beat read, stores the data in the internal buffer, writes the 16 beats to the destination, and waits for the corresponding write response. It then updates the source and destination addresses and performs the remaining 2-beat transfer.

This ensures that every AXI burst remains within the supported 16-beat limit.

### Byte-Lane Steering and Error Handling

The DMA supports dynamic data steering for different transfer widths and destination alignments. For **8-bit and 16-bit transfers**, as well as unaligned destination addresses, the controller calculates the appropriate byte offset and generates the corresponding `WSTRB` value. The data is shifted accordingly so that it is placed on the correct byte lanes of the AXI data bus.

The design also incorporates hardware-level memory boundary protection. If the DMA attempts to access an address outside the valid range of the memory slave, the slave detects the violation on the corresponding beat and prevents the invalid memory operation.

The slave then generates an AXI `SLVERR` response (`2'b10`). The DMA monitors the AXI response channels and records the error in its APB-visible Status register.
