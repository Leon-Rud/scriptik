use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::SampleFormat;
use hound::{WavSpec, WavWriter};
use std::io::BufWriter;
use std::fs::File;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

const TARGET_SAMPLE_RATE: u32 = 16000;
const TARGET_CHANNELS: u16 = 1;

pub struct Recorder {
    recording: Arc<AtomicBool>,
    output_path: PathBuf,
}

impl Recorder {
    pub fn new() -> Self {
        let temp_dir = std::env::temp_dir().join("scriptik");
        std::fs::create_dir_all(&temp_dir).ok();
        Self {
            recording: Arc::new(AtomicBool::new(false)),
            output_path: temp_dir.join("recording.wav"),
        }
    }

    pub fn output_path(&self) -> &PathBuf {
        &self.output_path
    }

    pub fn is_recording(&self) -> bool {
        self.recording.load(Ordering::Relaxed)
    }

    pub fn start(&self) -> Result<(), String> {
        if self.is_recording() {
            return Err("Already recording".to_string());
        }

        let host = cpal::default_host();
        let device = host.default_input_device()
            .ok_or("No audio input device found")?;

        let supported_config = device.default_input_config()
            .map_err(|e| format!("Failed to get input config: {e}"))?;

        let sample_rate = supported_config.sample_rate().0;
        let channels = supported_config.channels();
        let sample_format = supported_config.sample_format();

        let samples: Arc<Mutex<Vec<f32>>> = Arc::new(Mutex::new(Vec::new()));
        let samples_clone = samples.clone();

        let recording_flag = self.recording.clone();
        recording_flag.store(true, Ordering::Relaxed);

        let output_path = self.output_path.clone();
        let recording_for_thread = recording_flag.clone();

        std::thread::spawn(move || {
            let err_fn = |err| eprintln!("Audio stream error: {err}");

            let stream = match sample_format {
                SampleFormat::F32 => {
                    let samples = samples_clone.clone();
                    device.build_input_stream(
                        &supported_config.into(),
                        move |data: &[f32], _: &cpal::InputCallbackInfo| {
                            if let Ok(mut buf) = samples.lock() {
                                buf.extend_from_slice(data);
                            }
                        },
                        err_fn,
                        None,
                    )
                }
                SampleFormat::I16 => {
                    let samples = samples_clone.clone();
                    device.build_input_stream(
                        &supported_config.into(),
                        move |data: &[i16], _: &cpal::InputCallbackInfo| {
                            if let Ok(mut buf) = samples.lock() {
                                buf.extend(data.iter().map(|&s| s as f32 / i16::MAX as f32));
                            }
                        },
                        err_fn,
                        None,
                    )
                }
                _ => {
                    eprintln!("Unsupported sample format: {sample_format:?}");
                    recording_for_thread.store(false, Ordering::Relaxed);
                    return;
                }
            };

            let stream = match stream {
                Ok(s) => s,
                Err(e) => {
                    eprintln!("Failed to build audio stream: {e}");
                    recording_for_thread.store(false, Ordering::Relaxed);
                    return;
                }
            };

            if let Err(e) = stream.play() {
                eprintln!("Failed to start audio stream: {e}");
                recording_for_thread.store(false, Ordering::Relaxed);
                return;
            }

            while recording_for_thread.load(Ordering::Relaxed) {
                std::thread::sleep(std::time::Duration::from_millis(50));
            }

            drop(stream);

            let raw_samples = samples_clone.lock().unwrap().clone();
            if let Err(e) = write_wav(&output_path, &raw_samples, sample_rate, channels) {
                eprintln!("Failed to write WAV: {e}");
            }
        });

        Ok(())
    }

    pub fn stop(&self) {
        self.recording.store(false, Ordering::Relaxed);
    }
}

fn write_wav(path: &PathBuf, samples: &[f32], source_rate: u32, channels: u16) -> Result<(), String> {
    let mono: Vec<f32> = if channels > 1 {
        samples.chunks(channels as usize)
            .map(|chunk| chunk.iter().sum::<f32>() / channels as f32)
            .collect()
    } else {
        samples.to_vec()
    };

    let resampled = if source_rate != TARGET_SAMPLE_RATE {
        let ratio = TARGET_SAMPLE_RATE as f64 / source_rate as f64;
        let new_len = (mono.len() as f64 * ratio) as usize;
        (0..new_len)
            .map(|i| {
                let src_idx = i as f64 / ratio;
                let idx = src_idx as usize;
                let frac = src_idx - idx as f64;
                let s0 = mono.get(idx).copied().unwrap_or(0.0);
                let s1 = mono.get(idx + 1).copied().unwrap_or(s0);
                (s0 as f64 * (1.0 - frac) + s1 as f64 * frac) as f32
            })
            .collect()
    } else {
        mono
    };

    let spec = WavSpec {
        channels: TARGET_CHANNELS,
        sample_rate: TARGET_SAMPLE_RATE,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };

    let file = File::create(path).map_err(|e| format!("Failed to create WAV file: {e}"))?;
    let mut writer = WavWriter::new(BufWriter::new(file), spec)
        .map_err(|e| format!("Failed to create WAV writer: {e}"))?;

    for sample in &resampled {
        let s = (*sample * i16::MAX as f32).clamp(i16::MIN as f32, i16::MAX as f32) as i16;
        writer.write_sample(s).map_err(|e| format!("Failed to write sample: {e}"))?;
    }

    writer.finalize().map_err(|e| format!("Failed to finalize WAV: {e}"))?;
    Ok(())
}
