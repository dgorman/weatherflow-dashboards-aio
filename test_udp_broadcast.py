#!/usr/bin/env python3
"""
Simple UDP Broadcast Test Program

This script tests UDP broadcast packet reception to verify that the OS/network
can receive broadcast packets before debugging the WeatherFlow collector.

Usage:
  python3 test_udp_broadcast.py

Expected behavior:
  - Binds to 0.0.0.0:50222 with SO_BROADCAST enabled
  - Prints any UDP packets received on port 50222
  - Decodes and displays JSON payloads if possible
"""

import socket
import json
import sys
from datetime import datetime


def main():
    UDP_IP = "0.0.0.0"
    UDP_PORT = 50222
    
    print(f"=== UDP Broadcast Reception Test ===")
    print(f"Timestamp: {datetime.now()}")
    print(f"Binding to: {UDP_IP}:{UDP_PORT}")
    print(f"Waiting for UDP packets...")
    print(f"Press Ctrl+C to exit\n")
    
    # Create UDP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    # Enable SO_BROADCAST to receive broadcast packets
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    
    # Enable SO_REUSEADDR to allow multiple processes to bind
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    
    try:
        # Bind to the port
        sock.bind((UDP_IP, UDP_PORT))
        print(f"✓ Socket bound successfully to {UDP_IP}:{UDP_PORT}")
        print(f"✓ SO_BROADCAST enabled: {sock.getsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST)}")
        print(f"✓ SO_REUSEADDR enabled: {sock.getsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR)}")
        print(f"\n--- Listening for packets ---\n")
        
        packet_count = 0
        
        while True:
            # Receive data
            data, addr = sock.recvfrom(4096)
            packet_count += 1
            
            timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
            print(f"[{timestamp}] Packet #{packet_count} from {addr[0]}:{addr[1]}")
            print(f"  Size: {len(data)} bytes")
            
            # Try to decode as JSON
            try:
                decoded = json.loads(data.decode('utf-8'))
                print(f"  Type: {decoded.get('type', 'unknown')}")
                if 'serial_number' in decoded:
                    print(f"  Device: {decoded['serial_number']}")
                if 'hub_sn' in decoded:
                    print(f"  Hub: {decoded['hub_sn']}")
                # Pretty print the JSON (truncated)
                json_str = json.dumps(decoded, indent=2)
                lines = json_str.split('\n')
                if len(lines) > 10:
                    print(f"  Data: {chr(10).join(lines[:10])}")
                    print(f"       ... ({len(lines)-10} more lines)")
                else:
                    print(f"  Data: {json_str}")
            except (json.JSONDecodeError, UnicodeDecodeError) as e:
                # Not JSON or not UTF-8, show raw data (first 100 bytes)
                print(f"  Raw data: {data[:100]}")
            
            print()
            
    except KeyboardInterrupt:
        print(f"\n\n=== Test Summary ===")
        print(f"Total packets received: {packet_count}")
        print(f"Test completed successfully!")
    except Exception as e:
        print(f"\n✗ Error: {e}")
        sys.exit(1)
    finally:
        sock.close()
        print(f"Socket closed.")


if __name__ == "__main__":
    main()
