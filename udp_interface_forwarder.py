#!/usr/bin/env python3 -u
"""
UDP Packet Forwarder using libpcap/raw sockets

Captures UDP packets on port 50222 at the interface level (bypassing kernel's
broadcast filtering) and forwards them to localhost:50222 as unicast.

This works around the Linux kernel limitation where 255.255.255.255 broadcasts
don't get delivered to application sockets on different subnets.

Requires: root privileges (for packet capture)
"""

import socket
import sys
import time
import logging
import signal

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# Try to import scapy for packet capture
try:
    from scapy.all import sniff, UDP
except ImportError:
    logger.error("scapy is required. Install with: apt-get install python3-scapy")
    sys.exit(1)

CAPTURE_PORT = 50222
FORWARD_HOST = "127.0.0.1"
FORWARD_PORT = 50222

# Global flag for graceful shutdown
shutdown_flag = False

def signal_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    global shutdown_flag
    logger.info(f"Received signal {signum}, initiating graceful shutdown...")
    shutdown_flag = True


def forward_packet(packet):
    """Forward captured UDP packet to localhost"""
    global shutdown_flag
    if shutdown_flag:
        return
    
    if UDP in packet and packet[UDP].dport == CAPTURE_PORT:
        # Extract the UDP payload
        udp_data = bytes(packet[UDP].payload)
        
        # Forward as unicast to localhost
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.sendto(udp_data, (FORWARD_HOST, FORWARD_PORT))
            logger.debug(f"Forwarded {len(udp_data)} bytes from {packet[0][1].src}")
        except Exception as e:
            logger.error(f"Error forwarding packet: {e}")
        finally:
            sock.close()

def main():
    """Main forwarder loop"""
    global shutdown_flag
    
    # Register signal handlers for graceful shutdown
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    logger.info("="*60)
    logger.info("UDP Packet Forwarder (Interface Level)")
    logger.info("="*60)
    logger.info(f"Capturing UDP packets on port {CAPTURE_PORT}")
    logger.info(f"Forwarding to: {FORWARD_HOST}:{FORWARD_PORT}")
    logger.info("Press Ctrl+C to exit")
    logger.info("="*60)
    
    try:
        # Capture UDP packets on port 50222 at interface level
        sniff(
            filter=f"udp port {CAPTURE_PORT}",
            prn=forward_packet,
            store=0,  # Don't store packets in memory
            stop_filter=lambda x: shutdown_flag  # Stop when shutdown flag is set
        )
    except KeyboardInterrupt:
        logger.info("Received keyboard interrupt")
    except Exception as e:
        logger.error(f"Error: {e}")
        logger.error("Make sure you're running as root (sudo)")
        return 1
    finally:
        logger.info("Forwarder stopped")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
