package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

type SpeakRequest struct {
	Prompt string `json:"prompt"`
	Locale string `json:"locale"`
	Voice  string `json:"voice"`
	Mode   string `json:"mode"`
}

type JSONOutput struct {
	Status      string `json:"status"`
	Prompt      string `json:"prompt"`
	OutputPath  string `json:"output_path"`
	PromptLen   int    `json:"prompt_length"`
	Timestamp   string `json:"timestamp"`
	NativeMode  bool   `json:"native_mode"`
	DryRun      bool   `json:"dry_run,omitempty"`
}

var (
	outputWav  string
	host       string
	port       string
	jsonOut    bool
	dryRun     bool
	nativeMode bool
)

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil || !os.IsNotExist(err)
}

func main() {
	var rootCmd = &cobra.Command{
		Use:   "griffintts [text]",
		Short: "Synthesizes Jibo's authentic voice locally on macOS",
		Long: `griffintts is an agent-aware CLI that brings Jibo's original "Griffin"
vocal character to life locally on macOS. It operates by coordinating
with Jibo's native compiled 32-bit ARM synthesis engine running under
user-mode emulation inside a lightweight local container, OR via a 100%
native macOS standalone HTS synthesizer using Jibo's classic en_us model.`,
		Example: `  # Synthesize text directly (Container-backed modern model)
  griffintts "Hi there! I am Jibo."

  # Synthesize 100% natively on macOS without any containers (Classic model)
  griffintts --native "Hello, synthesized natively on Mac!"

  # Synthesize to a custom output path
  griffintts -ow hello.wav "Welcome back."

  # Agent-mode JSON output (with dry-run safety validation)
  griffintts --json --dry-run --native "Validating this text."`,
		Args: cobra.ArbitraryArgs,
		Run: func(cmd *cobra.Command, args []string) {
			executeSynthesis(args)
		},
	}

	// Define flags (Standard Cobra & Viper integration)
	rootCmd.Flags().StringVarP(&outputWav, "ow", "o", "output.wav", "Path to save the synthesized WAV file")
	rootCmd.Flags().StringVar(&host, "host", "localhost", "TTS container host")
	rootCmd.Flags().StringVarP(&port, "port", "p", "8089", "TTS container port")
	rootCmd.Flags().BoolVar(&jsonOut, "json", false, "Output in machine-readable JSON format (AX)")
	rootCmd.Flags().BoolVar(&dryRun, "dry-run", false, "Dry run validation without modifying files or triggering synthesis (AX)")
	rootCmd.Flags().BoolVarP(&nativeMode, "native", "n", false, "Use the 100% native macOS HTS standalone synthesizer (no containers)")

	// Bind flags to Viper
	viper.BindPFlag("ow", rootCmd.Flags().Lookup("ow"))
	viper.BindPFlag("host", rootCmd.Flags().Lookup("host"))
	viper.BindPFlag("port", rootCmd.Flags().Lookup("port"))
	viper.BindPFlag("json", rootCmd.Flags().Lookup("json"))
	viper.BindPFlag("dry-run", rootCmd.Flags().Lookup("dry-run"))
	viper.BindPFlag("native", rootCmd.Flags().Lookup("native"))

	viper.SetEnvPrefix("GRIFFINTTS")
	viper.AutomaticEnv()

	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func executeSynthesis(args []string) {
	outWav := viper.GetString("ow")
	targetHost := viper.GetString("host")
	targetPort := viper.GetString("port")
	isJSON := viper.GetBool("json")
	isDryRun := viper.GetBool("dry-run")
	isNative := viper.GetBool("native")

	// Check NO_COLOR support (Dual-Mode UX)
	useColor := os.Getenv("NO_COLOR") == ""

	// Gather prompt from arguments or standard input
	prompt := strings.Join(args, " ")
	if prompt == "" {
		stat, _ := os.Stdin.Stat()
		if (stat.Mode() & os.ModeCharDevice) == 0 {
			bytesData, err := io.ReadAll(os.Stdin)
			if err == nil {
				prompt = strings.TrimSpace(string(bytesData))
			}
		}
	}

	if prompt == "" {
		printErrorAndHint("Error: No text prompt provided. Provide text as arguments or via stdin.",
			"Usage Hint: griffintts [options] \"text to speak\"")
		os.Exit(1)
	}

	// Verify ffmpeg exists on host (Fail Fast & Proactive Error Hint)
	_, err := exec.LookPath("ffmpeg")
	if err != nil {
		printErrorAndHint("Error: ffmpeg was not found in your PATH.",
			"Proactive Hint: Run 'brew install ffmpeg' to install it natively on macOS.")
		os.Exit(1)
	}

	// 100% NATIVE MAC MODE (No Containers)
	if isNative {
		if !isJSON && !isDryRun {
			if useColor {
				fmt.Print("\033[34m[INFO]\033[0m Utilizing native standalone macOS HTS synthesizer...\n")
			} else {
				fmt.Print("[INFO] Utilizing native standalone macOS HTS synthesizer...\n")
			}
		}

		// Find project path (relative to the tools directory)
		wd, _ := os.Getwd()
		assetsDir := filepath.Join(wd, "tools/griffintts/assets/en_us")
		enginePath := filepath.Join(wd, "tools/griffintts/hts_engine_API/src/build/bin/hts_engine")
		
		// Fallback paths if working directory is inside the tools subdirectory
		if !fileExists(assetsDir) {
			assetsDir = filepath.Join(wd, "assets/en_us")
			enginePath = filepath.Join(wd, "hts_engine_API/src/build/bin/hts_engine")
		}

		if !fileExists(assetsDir) {
			printErrorAndHint("Error: Extracted voice assets directory 'assets/en_us' not found.",
				"Proactive Hint: Ensure you are running from the project root or copy assets/en_us locally.")
			os.Exit(1)
		}

		if !fileExists(enginePath) {
			printErrorAndHint("Error: Natively compiled hts_engine binary not found.",
				"Proactive Hint: Run 'make griffintts' to compile the hts_engine_API and wrappers.")
			os.Exit(1)
		}

		// Handle Mutative Safety: Dry Run
		if isDryRun {
			output := JSONOutput{
				Status:     "validated",
				Prompt:     prompt,
				OutputPath: outWav,
				PromptLen:  len(prompt),
				Timestamp:  time.Now().Format(time.RFC3339),
				NativeMode: true,
				DryRun:     true,
			}
			if isJSON {
				jsonBytes, _ := json.MarshalIndent(output, "", "  ")
				fmt.Println(string(jsonBytes))
			} else {
				if useColor {
					fmt.Printf("\033[32m[PASS]\033[0m Dry-run validation successful! Target Output: %s (NATIVE)\n", outWav)
				} else {
					fmt.Printf("[PASS] Dry-run validation successful! Target Output: %s (NATIVE)\n", outWav)
				}
			}
			return
		}

		// Load Jibo Pronunciation Dictionary
		if !isJSON {
			fmt.Println("Loading Jibo pronunciation lexicon...")
		}
		dictMap, err := parseDictionary(filepath.Join(assetsDir, "en_us.dictionary"))
		if err != nil {
			printErrorAndHint(fmt.Sprintf("Error: Failed to load Jibo dictionary: %v", err), "")
			os.Exit(1)
		}

		// Phonetize the input prompt dynamically!
		if !isJSON {
			fmt.Println("Translating text to phonemes...")
		}
		phones := phonetizeText(prompt, dictMap)

		// Generate HTS Labels
		phoneFeats, err := parsePhones(filepath.Join(assetsDir, "en_us.phones"))
		if err != nil {
			printErrorAndHint(fmt.Sprintf("Error: Failed to parse phone characteristics: %v", err), "")
			os.Exit(1)
		}

		labels := generateLabels(phones, phoneFeats)
		
		tempLab, err := os.CreateTemp("", "griffintts-*.lab")
		if err != nil {
			printErrorAndHint(fmt.Sprintf("Error: Failed to create temporary label: %v", err), "")
			os.Exit(1)
		}
		tempLabPath := tempLab.Name()
		defer os.Remove(tempLabPath)

		for _, lbl := range labels {
			tempLab.WriteString(lbl + "\n")
		}
		tempLab.Close()

		// Run native hts_engine with Jibo's specific alpha/beta constants and a +16 dB gain boost
		voicePath := filepath.Join(assetsDir, "en_us.voice")
		synthCmd := exec.Command(enginePath, 
			"-m", voicePath, 
			"-a", "0.53", 
			"-b", "0.4", 
			"-g", "16", 
			"-ow", outWav, 
			tempLabPath,
		)
		var synthErr bytes.Buffer
		synthCmd.Stderr = &synthErr
		if err := synthCmd.Run(); err != nil {
			printErrorAndHint(fmt.Sprintf("Error: Native HTS speech synthesis failed: %v", err),
				fmt.Sprintf("Stderr: %s", synthErr.String()))
			os.Exit(1)
		}

		if isJSON {
			output := JSONOutput{
				Status:     "success",
				Prompt:     prompt,
				OutputPath: outWav,
				PromptLen:  len(prompt),
				Timestamp:  time.Now().Format(time.RFC3339),
				NativeMode: true,
			}
			jsonBytes, _ := json.MarshalIndent(output, "", "  ")
			fmt.Println(string(jsonBytes))
		} else {
			if useColor {
				fmt.Printf("\033[32m[PASS]\033[0m Standalone native voice synthesized cleanly and saved to: \033[1m%s\033[0m\n", outWav)
			} else {
				fmt.Printf("[PASS] Standalone native voice synthesized cleanly and saved to: %s\n", outWav)
			}
		}
		return
	}

	// CONTAINER MODE (Option B WORLD Vocoder Mode)
	// Verify container system commands (Proactive Error Hint)
	_, err = exec.LookPath("container")
	if err != nil {
		printErrorAndHint("Error: Apple container platform CLI was not found in your PATH.",
			"Proactive Hint: Ensure Apple's container platform is installed and available in your PATH.")
		os.Exit(1)
	}

	// Ensure container is running/ready
	if !isJSON && !isDryRun {
		if useColor {
			fmt.Print("\033[34m[INFO]\033[0m Verifying TTS container environment...\n")
		} else {
			fmt.Print("[INFO] Verifying TTS container environment...\n")
		}
	}

	err = ensureContainerRunning(isJSON, isDryRun, useColor)
	if err != nil {
		printErrorAndHint(fmt.Sprintf("Error: Failed to verify Jibo TTS container: %v", err),
			"Proactive Hint: Start Apple's container backend first by executing: 'container system start'")
		os.Exit(1)
	}

	// Handle Mutative Safety: Dry Run
	if isDryRun {
		output := JSONOutput{
			Status:     "validated",
			Prompt:     prompt,
			OutputPath: outWav,
			PromptLen:  len(prompt),
			Timestamp:  time.Now().Format(time.RFC3339),
			DryRun:     true,
		}
		if isJSON {
			jsonBytes, _ := json.MarshalIndent(output, "", "  ")
			fmt.Println(string(jsonBytes))
		} else {
			if useColor {
				fmt.Printf("\033[32m[PASS]\033[0m Dry-run validation successful! Target Output: %s\n", outWav)
			} else {
				fmt.Printf("[PASS] Dry-run validation successful! Target Output: %s\n", outWav)
			}
		}
		return
	}

	// Truncate output.raw to 0 bytes before synthesis to prevent phrase accumulation (container-retention issue)
	if !isJSON {
		if useColor {
			fmt.Print("\033[34m[INFO]\033[0m Clearing speech buffer inside container...\n")
		} else {
			fmt.Print("[INFO] Clearing speech buffer inside container...\n")
		}
	}
	truncCmd := exec.Command("container", "exec", "tts_run", "truncate", "-s", "0", "/app/output.raw")
	_ = truncCmd.Run() // Run silently to prevent dry-run/AX noise

	// Trigger synthesis POST request
	if !isJSON {
		if useColor {
			fmt.Printf("\033[36m[TTS]\033[0m Synthesizing: \033[1m\"%s\"\033[0m...\n", prompt)
		} else {
			fmt.Printf("[TTS] Synthesizing: \"%s\"...\n", prompt)
		}
	}

	speakURL := fmt.Sprintf("http://%s:%s/tts_speak", targetHost, targetPort)
	reqBody := SpeakRequest{
		Prompt: prompt,
		Locale: "en-US",
		Voice:  "GRIFFIN",
		Mode:   "TEXT",
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		printErrorAndHint(fmt.Sprintf("Error: Failed to marshal request JSON: %v", err), "")
		os.Exit(1)
	}

	resp, err := http.Post(speakURL, "application/json", bytes.NewBuffer(jsonData))
	if err != nil {
		printErrorAndHint(fmt.Sprintf("Error: Failed to connect to local TTS service: %v", err),
			fmt.Sprintf("Proactive Hint: Verify if the background container is active or check port manually with: 'curl http://localhost:%s/'", targetPort))
		os.Exit(1)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusOK {
		printErrorAndHint(fmt.Sprintf("Error: Speak request returned unexpected status code: %d", resp.StatusCode), "")
		os.Exit(1)
	}

	// Wait briefly for disk flushing inside the container
	time.Sleep(500 * time.Millisecond)

	// Copy output.raw out of container to a temporary file
	tempRaw, err := os.CreateTemp("", "griffintts-*.raw")
	if err != nil {
		printErrorAndHint(fmt.Sprintf("Error: Failed to create temporary file: %v", err), "")
		os.Exit(1)
	}
	tempRawPath := tempRaw.Name()
	tempRaw.Close()
	defer os.Remove(tempRawPath)

	if !isJSON {
		fmt.Println("Copying synthesized PCM data from container...")
	}
	cpCmd := exec.Command("container", "cp", "tts_run:/app/output.raw", tempRawPath)
	var cpErr bytes.Buffer
	cpCmd.Stderr = &cpErr
	if err := cpCmd.Run(); err != nil {
		printErrorAndHint(fmt.Sprintf("Error: Failed to copy PCM file from container: %v", err),
			fmt.Sprintf("Stderr: %s\nProactive Hint: Verify the container state by executing 'container ls'", cpErr.String()))
		os.Exit(1)
	}

	// Convert raw PCM to WAV using ffmpeg on host
	if !isJSON {
		fmt.Printf("Converting PCM to WAV at %s...\n", outWav)
	}
	ffmpegCmd := exec.Command("ffmpeg", "-y", "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", tempRawPath, outWav)
	var ffmpegErr bytes.Buffer
	ffmpegCmd.Stderr = &ffmpegErr
	if err := ffmpegCmd.Run(); err != nil {
		printErrorAndHint(fmt.Sprintf("Error: Failed to convert raw PCM to WAV: %v", err),
			fmt.Sprintf("Stderr: %s\nProactive Hint: Ensure ffmpeg has permissions to write to %s", ffmpegErr.String(), outWav))
		os.Exit(1)
	}

	if isJSON {
		output := JSONOutput{
			Status:     "success",
			Prompt:     prompt,
			OutputPath: outWav,
			PromptLen:  len(prompt),
			Timestamp:  time.Now().Format(time.RFC3339),
		}
		jsonBytes, _ := json.MarshalIndent(output, "", "  ")
		fmt.Println(string(jsonBytes))
	} else {
		if useColor {
			fmt.Printf("\033[32m[PASS]\033[0m Jibo's voice synthesized cleanly and saved to: \033[1m%s\033[0m\n", outWav)
		} else {
			fmt.Printf("[PASS] Jibo's voice synthesized cleanly and saved to: %s\n", outWav)
		}
	}
}

func ensureContainerRunning(isJSON bool, isDryRun bool, useColor bool) error {
	// Check if tts_run exists
	inspectCmd := exec.Command("container", "inspect", "tts_run")
	output, err := inspectCmd.Output()
	
	if err != nil {
		// Container doesn't exist, create and run it
		if isDryRun {
			return nil // Validation of environment is ok for dry-run
		}
		if !isJSON {
			if useColor {
				fmt.Println("\033[33m[WARN]\033[0m TTS container 'tts_run' does not exist. Creating and running it...")
			} else {
				fmt.Println("[WARN] TTS container 'tts_run' does not exist. Creating and running it...")
			}
		}
		runCmd := exec.Command("container", "run", "-d", "--name", "tts_run", "-p", "8089:8089", "-e", "LD_LIBRARY_PATH=/app/assets/lib:/usr/lib/arm-linux-gnueabihf", "griffintts")
		var runErr bytes.Buffer
		runCmd.Stderr = &runErr
		if err := runCmd.Run(); err != nil {
			return fmt.Errorf("failed to run container: %v, %s", err, runErr.String())
		}
		// Give it a moment to boot
		time.Sleep(3 * time.Second)
		return nil
	}

	// Check if running
	if strings.Contains(string(output), `"running"`) || strings.Contains(string(output), "running") {
		return nil
	}

	// Exists but stopped, start it
	if isDryRun {
		return nil
	}
	if !isJSON {
		if useColor {
			fmt.Println("\033[33m[WARN]\033[0m TTS container 'tts_run' is stopped. Starting it...")
		} else {
			fmt.Println("[WARN] TTS container 'tts_run' is stopped. Starting it...")
		}
	}
	startCmd := exec.Command("container", "start", "tts_run")
	var startErr bytes.Buffer
	startCmd.Stderr = &startErr
	if err := startCmd.Run(); err != nil {
		return fmt.Errorf("failed to start container: %v, %s", err, startErr.String())
	}
	time.Sleep(2 * time.Second)
	return nil
}

func printErrorAndHint(errMsg string, hintMsg string) {
	fmt.Fprintf(os.Stderr, "%s\n", errMsg)
	if hintMsg != "" {
		fmt.Fprintf(os.Stderr, "\033[33m%s\033[0m\n", hintMsg)
	}
}

// Phone parsing, dictionary, and full-context HTS label generation helper routines

func parseDictionary(dictPath string) (map[string][]string, error) {
	wordMap := make(map[string][]string)
	file, err := os.Open(dictPath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.Split(line, "|")
		if len(parts) >= 3 {
			word := strings.ToLower(strings.TrimSpace(parts[0]))
			// Parse syllables and gather raw phones
			var phonemes []string
			for i := 2; i < len(parts); i++ {
				syl := strings.TrimSpace(parts[i])
				sylParts := strings.Fields(syl)
				if len(sylParts) > 0 {
					// Index 0 of sylParts is the stress number, the rest are phonemes
					for j := 1; j < len(sylParts); j++ {
						phonemes = append(phonemes, strings.ToLower(sylParts[j]))
					}
				}
			}
			if len(phonemes) > 0 {
				wordMap[word] = phonemes
			}
		}
	}
	return wordMap, scanner.Err()
}

func phonetizeText(text string, dictMap map[string][]string) []string {
	// Clean text: strip punctuation and split by whitespace into words
	reg, _ := regexp.Compile("[^a-zA-Z0-9'\\s]+")
	cleaned := reg.ReplaceAllString(text, "")
	rawWords := strings.Fields(strings.ToLower(cleaned))

	// Initial starting pause
	phones := []string{"lpau"}

	for _, w := range rawWords {
		if w == "" {
			continue
		}
		if phList, ok := dictMap[w]; ok {
			phones = append(phones, phList...)
		} else {
			// Fail-safe: if a word is not in the dictionary, spell it out letter by letter!
			// Jibo's dictionary has explicit phonetic entries for aletter, bletter, etc.
			for _, ch := range w {
				letterName := fmt.Sprintf("%cletter", ch)
				if letterPhList, found := dictMap[letterName]; found {
					phones = append(phones, letterPhList...)
				}
			}
		}
	}

	// Trailing ending pause
	phones = append(phones, "lpau")
	return phones
}

func parsePhones(phonesPath string) (map[string][]string, error) {
	phoneFeatures := make(map[string][]string)
	file, err := os.Open(phonesPath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.Fields(line)
		if len(parts) >= 10 {
			phoneName := strings.ToLower(parts[0])
			phoneFeatures[phoneName] = parts[1:10]
		}
	}
	return phoneFeatures, scanner.Err()
}

func generateLabels(phones []string, phoneFeatures map[string][]string) []string {
	var labels []string

	for i, centerPhone := range phones {
		lbl := make(map[string]string)

		// Context window
		var plli, pli, pci, pri, prri string
		if i-2 >= 0 {
			plli = phones[i-2]
		} else {
			plli = "lpau"
		}
		if i-1 >= 0 {
			pli = phones[i-1]
		} else {
			pli = "lpau"
		}
		pci = centerPhone
		if i+1 < len(phones) {
			pri = phones[i+1]
		} else {
			pri = "lpau"
		}
		if i+2 < len(phones) {
			prri = phones[i+2]
		} else {
			prri = "lpau"
		}

		lbl["PLLI"] = plli
		lbl["PLI"] = pli
		lbl["PCI"] = fmt.Sprintf("-%s+", pci)
		lbl["PRI"] = pri
		lbl["PRRI"] = prri

		lbl["PSFW"] = "1"
		lbl["PSBW"] = "1"
		lbl["PWFW"] = fmt.Sprintf("%d", i)
		lbl["PWBW"] = fmt.Sprintf("%d", len(phones)-i-1)

		mapPhoneFeats := func(phone string, prefix string) {
			feats, ok := phoneFeatures[phone]
			if !ok {
				feats = []string{"XX", "XX", "XX", "XX", "XX", "XX", "XX", "XX", "XX"}
			}
			lbl[prefix+"VC"] = feats[0]
			lbl[prefix+"VL"] = feats[1]
			lbl[prefix+"VH"] = feats[2]
			lbl[prefix+"VF"] = feats[3]
			lbl[prefix+"VR"] = feats[4]
			lbl[prefix+"VRh"] = feats[5]
			lbl[prefix+"CT"] = feats[6]
			lbl[prefix+"CPA"] = feats[7]
			lbl[prefix+"Vo"] = feats[8]
		}

		mapPhoneFeats(plli, "PLL")
		mapPhoneFeats(pli, "PL")
		mapPhoneFeats(pci, "PC")
		mapPhoneFeats(pri, "PR")
		mapPhoneFeats(prri, "PRR")

		lbl["SLS"] = "0"
		if centerPhone == "e" || centerPhone == "ou" {
			lbl["SCS"] = "1"
		} else {
			lbl["SCS"] = "0"
		}
		lbl["SRS"] = "0"
		lbl["SLA"] = "0"
		lbl["SCA"] = "0"
		lbl["SRA"] = "0"
		lbl["SLNP"] = "0"
		lbl["SCNP"] = "2"
		lbl["SRNP"] = "2"

		for _, k := range []string{"SWFW", "SWBW", "SPhFW", "SPhBW", "SNPSS", "SNFSS", "SDPSS", "SDFSS", "SNPAS", "SNFAS", "SDPAS", "SDFAS"} {
			lbl[k] = "0"
		}

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

		lbl["PhNS"] = "2"
		lbl["PhNW"] = "1"
		lbl["PhT"] = "0"

		// Construct joined pipe string in a deterministic order for HTS matching consistency
		keys := []string{
			"PLLI", "PLI", "PCI", "PRI", "PRRI", "PSFW", "PSBW", "PWFW", "PWBW",
			"PLLVC", "PLLVL", "PLLVH", "PLLVF", "PLLVR", "PLLVRh", "PLLCT", "PLLCPA", "PLLVo",
			"PLVC", "PLVL", "PLVH", "PLVF", "PLVR", "PLVRh", "PLCT", "PLCPA", "PLVo",
			"PCVC", "PCVL", "PCVH", "PCVF", "PCVR", "PCVRh", "PCCT", "PCCPA", "PCVo",
			"PRVC", "PRVL", "PRVH", "PRVF", "PRVR", "PRVRh", "PRCT", "PRCPA", "PRVo",
			"PRRVC", "PRRVL", "PRRVH", "PRRVF", "PRRVR", "PRRVRh", "PRRCT", "PRRCPA", "PRRVo",
			"SLS", "SCS", "SRS", "SLA", "SCA", "SRA", "SLNP", "SCNP", "SRNP",
			"SWFW", "SWBW", "SPhFW", "SPhBW", "SNPSS", "SNFSS", "SDPSS", "SDFSS", "SNPAS", "SNFAS", "SDPAS", "SDFAS",
			"WLNP", "WCNP", "WRNP", "WLNS", "WCNS", "WRNS", "WLPOS", "WCPOS", "WRPOS", "WPhFW", "WPhBW", "WNPCW", "WNFCW", "WDPCW", "WDFCW", "WSS",
			"PhNS", "PhNW", "PhT",
		}

		var parts []string
		for _, k := range keys {
			parts = append(parts, fmt.Sprintf("%s:%s", k, lbl[k]))
		}
		labelString := "|" + strings.Join(parts, "|") + "|"
		labels = append(labels, labelString)
	}

	return labels
}
