import http.server
import json
import os
import sqlite3
import threading
import time

db_path = "/opt/portfolio/analytics.db"
proc_path = "/host/proc" if os.path.exists("/host/proc") else "/proc"

# Global variables for CPU usage calculation
prev_idle = 0.0
prev_total = 0.0
cpu_lock = threading.Lock()

def get_cpu_usage():
    global prev_idle, prev_total
    with cpu_lock:
        try:
            with open(f"{proc_path}/stat", "r") as f:
                line = f.readline()
            parts = line.split()
            if len(parts) >= 5:
                # user, nice, system, idle, iowait, irq, softirq, steal
                vals = [float(x) for x in parts[1:9]]
                idle = vals[3] + vals[4] # idle + iowait
                total = sum(vals)
                
                if prev_total == 0:
                    prev_idle = idle
                    prev_total = total
                    return 0.0
                
                idle_delta = idle - prev_idle
                total_delta = total - prev_total
                
                prev_idle = idle
                prev_total = total
                
                if total_delta == 0:
                    return 0.0
                
                usage = (1.0 - (idle_delta / total_delta)) * 100
                return round(max(0.0, min(100.0, usage)), 1)
        except Exception as e:
            print(f"Error reading CPU usage: {e}")
        return 0.0

def get_cpu_load():
    try:
        with open(f"{proc_path}/loadavg", "r") as f:
            content = f.read().strip()
        parts = content.split()
        if len(parts) > 0:
            return float(parts[0]) # 1-minute load average
    except Exception as e:
        print(f"Error reading CPU load: {e}")
    return 0.0

def get_mem_usage():
    try:
        mem_total = 0
        mem_avail = 0
        with open(f"{proc_path}/meminfo", "r") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    mem_total = int(line.split()[1])
                elif line.startswith("MemAvailable:"):
                    mem_avail = int(line.split()[1])
                if mem_total and mem_avail:
                    break
        if mem_total > 0:
            usage = (mem_total - mem_avail) / mem_total * 100
            return round(max(0.0, min(100.0, usage)), 1)
    except Exception as e:
        print(f"Error reading Memory: {e}")
    return 0.0

def get_uptime():
    try:
        with open(f"{proc_path}/uptime", "r") as f:
            uptime_seconds = float(f.readline().split()[0])
        
        days = int(uptime_seconds // 86400)
        hours = int((uptime_seconds % 86400) // 3600)
        minutes = int((uptime_seconds % 3600) // 60)
        seconds = int(uptime_seconds % 60)
        
        parts = []
        if days > 0:
            parts.append(f"{days}d")
        if hours > 0:
            parts.append(f"{hours}h")
        if minutes > 0:
            parts.append(f"{minutes}m")
        parts.append(f"{seconds}s")
        return " ".join(parts)
    except Exception as e:
        print(f"Error reading Uptime: {e}")
    return "0s"

def init_db():
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS hits (
            id INTEGER PRIMARY KEY,
            count INTEGER
        )
    """)
    cursor.execute("SELECT count FROM hits WHERE id = 1")
    if cursor.fetchone() is None:
        cursor.execute("INSERT INTO hits (id, count) VALUES (1, 0)")
    conn.commit()
    conn.close()

def increment_hits():
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("UPDATE hits SET count = count + 1 WHERE id = 1")
    cursor.execute("SELECT count FROM hits WHERE id = 1")
    count = cursor.fetchone()[0]
    conn.commit()
    conn.close()
    return count

def cpu_burner():
    # Burn CPU on a core for 5 seconds
    start_time = time.time()
    while time.time() - start_time < 5.0:
        _ = 9999 * 9999

def trigger_chaos():
    # Start 2 threads to burn both VM cores on e2-micro
    for _ in range(2):
        t = threading.Thread(target=cpu_burner)
        t.daemon = True
        t.start()

class MetricsHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Suppress request logging to keep outputs clean
        pass

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_GET(self):
        if self.path == '/api/stats':
            hits = increment_hits()
            cpu_util = get_cpu_usage()
            cpu_load = get_cpu_load() # Read from loadavg
            ram = get_mem_usage()
            uptime = get_uptime()
            
            payload = {
                "cpu": cpu_util,      # Real-time CPU usage percentage
                "cpu_load": cpu_load, # loadavg parsed CPU load
                "ram": ram,           # meminfo parsed RAM percentage
                "uptime": uptime,     # uptime parsed VM uptime
                "hits": hits          # SQLite DB page hits
            }
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps(payload).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/api/chaos':
            trigger_chaos()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "chaos triggered"}).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

def main():
    init_db()
    # Initialize CPU usage calculation
    get_cpu_usage()
    
    server_address = ('', 5000)
    httpd = http.server.HTTPServer(server_address, MetricsHandler)
    print("Metrics Daemon listening on port 5000...")
    httpd.serve_forever()

if __name__ == '__main__':
    main()
