#!/usr/bin/env python3
"""
UDP Broadcast to Unicast Relay for WeatherFlow Tempest

This script receives UDP broadcasts from the Tempest weather station
and forwards them as unicast packets to remote Kubernetes nodes.

This enables local weather data collection even when internet is down,
by relaying broadcasts from the Tempest (192.168.1.x) to Kubernetes 
nodes on a different subnet (192.168.2.x).

Usage:
    python3 udp_broadcast_relay.py
    
Configuration:
    Edit FORWARD_HOSTS below to add/remove target nodes
"""

import socket
import sys
import time

# Configuration
BROADCAST_PORT = 50222       # Port to listen for broadcasts

# List of Kubernetes nodes to forward to
FORWARD_HOSTS = [
    "192.168.2.22",  # node01
    "192.168.2.23",  # node02
    "192.168.2.24",  # node03
]
FORWARD_PORT = 50222         # Port to forward to

def main():
    print("=" * 60)
    print("UDP Broadcast to Kubernetes Nodes Relay")
    print("=" * 60)
    print(f"Listening for broadcasts on: 0.0.0.0:{BROADCAST_PORT}")
    print(f"Forwarding to nodes:")
    for host in FORWARD_HOSTS:
        print(f"  - {host}:{FORWARD_PORT}")
    print("Press Ctrl+C to exit")
    print("=" * 60)
    
    # Create socket to receive broadcasts
    recv_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    recv_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    recv_sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    
    try:
        recv_sock.bind(("0.0.0.0", BROADCAST_PORT))
        print(f"✓ Bound to 0.0.0.0:{BROADCAST_PORT}")
    except OSError as e:
        print(f"✗ Error binding to port {BROADCAST_PORT}: {e}")
        print(f"  Make sure no other process is using port {BROADCAST_PORT}")
        sys.exit(1)
    
    # Create socket to send unicast
    send_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    packet_count = 0
    forward_count = {host: 0 for host in FORWARD_HOSTS}
    last_print_time = time.time()
    
    try:
        while True:
            # Receive broadcast packet
            data, addr = recv_sock.recvfrom(4096)
            
            # Ignore packets from localhost (avoid relay loop)
            if addr[0] == "127.0.0.1" or addr[0].startswith("127.") or addr[0].startswith("192.168.2."):
                continue
            
            packet_count += 1
            
            # Forward as unicast to all Kubernetes nodes
            for host in FORWARD_HOSTS:
                try:
                    send_sock.sendto(data, (host, FORWARD_PORT))
                    forward_count[host] += 1
                except Exception as e:
                    print(f"✗ Error forwarding to {host}: {e}")
            
            # Print status every 10 seconds
            current_time = time.time()
            if current_time - last_print_time >= 10:
                print(f"[{time.strftime('%H:%M:%S')}] Total received: {packet_count} packets")
                for host in FORWARD_HOSTS:
                    print(f"  → {host}: {forward_count[host]} packets")
                last_print_time = current_time
            
    except KeyboardInterrupt:
        print(f"\n\n{'=' * 60}")
        print(f"Relay stopped. Total packets relayed: {packet_count}")
        print("=" * 60)
    except Exception as e:
        print(f"\n✗ Error: {e}")
    finally:
        recv_sock.close()
        send_sock.close()

if __name__ == "__main__":
    main()
