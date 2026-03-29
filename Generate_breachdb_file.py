import hashlib
import os

def generate_breach():
    print("--- PassGuard OS: Breach DB Generator ---")

    path = input("Enter the full path to your wordlist (e.g., C:/data/rockyou.txt): ").strip()

    path = path.replace('"', '').replace("'", "")

    if not os.path.isfile(path):
        print(f"❌ Error: File not found at {path}")
        return

    try:
        limit_str = input("Max entries to process (e.g., 500000) [Enter for ALL]: ").strip()
        limit = int(limit_str) if limit_str else 0
    except ValueError:
        print("❌ Invalid number. Defaulting to ALL.")
        limit = 0

    hashes = set()
    count = 0

    print(f"\nProcessing: {os.path.basename(path)}...")
    
    try:
        with open(path, 'r', encoding='latin-1') as f:
            for line in f:
                password = line.strip()
                if not password: continue
                h = hashlib.sha1(password.encode()).hexdigest()[:10]
                hashes.add(h)
                
                count += 1
                if limit > 0 and count >= limit:
                    break
                
                if count % 100000 == 0:
                    print(f"-> {count} passwords analyzed...")

        print(f"\nWriting {len(hashes)} unique hashes to 'breach_db.txt'...")
        with open('breach_db.txt', 'w') as out:
            for h in sorted(hashes):
                out.write(h + '\n')
                
        print(f"\n✅ SUCCESS!")
        print(f"Final file size: {os.path.getsize('breach_db.txt') / (1024*1024):.2f} MB")
        print("Move 'breach_db.txt' to your project's 'assets/' folder.")
        
    except Exception as e:
        print(f"❌ CRITICAL_ERROR: {e}")

if __name__ == "__main__":
    generate_breach()
