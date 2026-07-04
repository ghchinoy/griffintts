import sys
import time
import json
import threading
import websocket
import requests

def listen_ws(url, name):
    def on_message(ws, message):
        try:
            parsed = json.loads(message)
            formatted = json.dumps(parsed, indent=2)
            print(f"\n[{name} EVENT]\n{formatted}")
        except Exception:
            print(f"\n[{name} RAW]\n{message}")
    
    def on_error(ws, error):
        pass
        
    def on_close(ws, close_status_code, close_msg):
        pass

    ws = websocket.WebSocketApp(url,
                                on_message=on_message,
                                on_error=on_error,
                                on_close=on_close)
    ws.run_forever()

if __name__ == "__main__":
    host = "mars-bond-mesquite-cotton.local"
    port = "8089"
    text = "Hi there, I am Griffin, Jibo's voice."
    if len(sys.argv) > 1:
        text = " ".join(sys.argv[1:])

    print(f"Connecting to Jibo TTS event sockets...")
    # Start WebSocket threads
    paths = {
        "PHONES": f"ws://{host}:{port}/tts_phones",
        "TOKENS": f"ws://{host}:{port}/tts_tokens",
        "ANALYSIS": f"ws://{host}:{port}/tts_analysis"
    }

    threads = []
    for name, url in paths.items():
        t = threading.Thread(target=listen_ws, args=(url, name))
        t.daemon = True
        t.start()
        threads.append(t)

    # Let sockets connect
    time.sleep(1.0)

    print(f"Triggering TTS speak: '{text}'")
    # Trigger POST request
    speak_url = f"http://{host}:{port}/tts_speak"
    payload = {
        "prompt": text,
        "locale": "en-US",
        "voice": "GRIFFIN",
        "mode": "TEXT"
    }
    
    headers = {"Content-Type": "application/json"}
    try:
        response = requests.post(speak_url, json=payload, headers=headers, timeout=10)
        print(f"Speak response status: {response.status_code}")
    except Exception as e:
        print(f"Error triggering speak: {e}")

    # Wait for synthesis and audio events to finish
    time.sleep(5.0)
    print("\nCapture complete.")
    sys.exit(0)
