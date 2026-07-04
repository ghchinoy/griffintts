import sys
import subprocess
import os

def parse_phones(phones_path):
    phone_features = {}
    with open(phones_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) >= 10:
                phone_name = parts[0].lower()
                features = parts[1:10]
                phone_features[phone_name] = features
    return phone_features

def generate_full_context_labels(phones, phone_features):
    labels = []
    
    # We will format them as key:val and join with |
    for i, center_phone in enumerate(phones):
        lbl = {}
        
        # Phone context names (5-phone window)
        plli = phones[i - 2] if i - 2 >= 0 else "lpau"
        pli = phones[i - 1] if i - 1 >= 0 else "lpau"
        pci = center_phone
        pri = phones[i + 1] if i + 1 < len(phones) else "lpau"
        prri = phones[i + 2] if i + 2 < len(phones) else "lpau"
        
        lbl["PLLI"] = plli
        lbl["PLI"] = pli
        lbl["PCI"] = f"-{pci}+"
        lbl["PRI"] = pri
        lbl["PRRI"] = prri
        
        # Phone positions
        lbl["PSFW"] = "1"
        lbl["PSBW"] = "1"
        lbl["PWFW"] = str(i)
        lbl["PWBW"] = str(len(phones) - i - 1)
        
        # Helper to map phone features
        def map_phone_feats(phone, prefix):
            feats = phone_features.get(phone, ["XX"] * 9)
            lbl[f"{prefix}VC"] = feats[0]
            lbl[f"{prefix}VL"] = feats[1]
            lbl[f"{prefix}VH"] = feats[2]
            lbl[f"{prefix}VF"] = feats[3]
            lbl[f"{prefix}VR"] = feats[4]
            lbl[f"{prefix}VRh"] = feats[5]
            lbl[f"{prefix}CT"] = feats[6]
            lbl[f"{prefix}CPA"] = feats[7]
            lbl[f"{prefix}Vo"] = feats[8]
            
        map_phone_feats(plli, "PLL")
        map_phone_feats(pli, "PL")
        map_phone_feats(pci, "PC")
        map_phone_feats(pri, "PR")
        map_phone_feats(prri, "PRR")
        
        # Syllable / Word / Phrase defaults
        lbl["SLS"] = "0"
        lbl["SCS"] = "1" if center_phone in ["e", "ou"] else "0"
        lbl["SRS"] = "0"
        lbl["SLA"] = "0"
        lbl["SCA"] = "0"
        lbl["SRA"] = "0"
        lbl["SLNP"] = "0"
        lbl["SCNP"] = "2"
        lbl["SRNP"] = "2"
        
        # Syllable positional features
        for k in ["SWFW", "SWBW", "SPhFW", "SPhBW", "SNPSS", "SNFSS", "SDPSS", "SDFSS", "SNPAS", "SNFAS", "SDPAS", "SDFAS"]:
            lbl[k] = "0"
            
        # Word features
        lbl["WLNP"] = "4"
        lbl["WCNP"] = "4"
        lbl["WRNP"] = "4"
        lbl["WLNS"] = "2"
        lbl["WCNS"] = "2"
        lbl["WRNS"] = "2"
        lbl["WLPOS"] = "UH"
        lbl["WCPOS"] = "UH"
        lbl["WRPOS"] = "UH"
        lbl["WPhFW"] = "0"
        lbl["WPhBW"] = "0"
        lbl["WNPCW"] = "0"
        lbl["WNFCW"] = "0"
        lbl["WDPCW"] = "0"
        lbl["WDFCW"] = "0"
        lbl["WSS"] = "1"
        
        # Phrase features
        lbl["PhNS"] = "2"
        lbl["PhNW"] = "1"
        lbl["PhT"] = "0"
        
        # Build the final joined string
        parts = []
        for k, v in lbl.items():
            parts.append(f"{k}:{v}")
        label_string = "|".join(parts)
        label_string = f"|{label_string}|"
        labels.append(label_string)
        
    return labels

if __name__ == "__main__":
    phones_path = "tools/griffintts/assets/en_us/en_us.phones"
    voice_path = "tools/griffintts/assets/en_us/en_us.voice"
    engine_path = "tools/griffintts/hts_engine_API/src/build/bin/hts_engine"
    
    if not os.path.exists(phones_path):
        print(f"Error: phones file not found at {phones_path}")
        sys.exit(1)
        
    print("Parsing phone features...")
    phone_features = parse_phones(phones_path)
    
    # "Hello" phonemes: lpau (pause), h, e, l, ou, lpau (pause)
    hello_phones = ["lpau", "h", "e", "l", "ou", "lpau"]
    
    print(f"Generating full-context labels for sequence: {hello_phones}")
    labels = generate_full_context_labels(hello_phones, phone_features)
    
    lab_file_path = "tools/griffintts/hello_native.lab"
    with open(lab_file_path, "w") as f:
        for lbl in labels:
            f.write(f"{lbl}\n")
    print(f"HTS label file written to: {lab_file_path}")
    
    # Run hts_engine
    wav_file_path = "tools/griffintts/hello_native.wav"
    print(f"Synthesizing WAV file using native hts_engine...")
    cmd = [
        engine_path,
        "-m", voice_path,
        "-ow", wav_file_path,
        lab_file_path
    ]
    print(f"Executing: {' '.join(cmd)}")
    
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        print("\nHTS Engine execution completed successfully!")
        print(f"WAV output saved to: {wav_file_path}")
        print(f"WAV File size: {os.path.getsize(wav_file_path)} bytes")
    except subprocess.CalledProcessError as e:
        print(f"Error executing hts_engine: {e}")
        print(f"Stdout:\n{e.stdout}")
        print(f"Stderr:\n{e.stderr}")
        sys.exit(1)
