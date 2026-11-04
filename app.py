import gradio as gr
import torch
import yaml
import argparse
from modules.commons import str2bool

# Set up device and torch configurations
if torch.cuda.is_available():
    device = torch.device("cuda")
elif torch.backends.mps.is_available():
    device = torch.device("mps")
else:
    device = torch.device("cpu")

dtype = torch.float16 if device.type == "cuda" else torch.float32

# Global variables to store model instances
vc_wrapper_v1 = None
vc_wrapper_v2 = None


def load_v2_models(args):
    from hydra.utils import instantiate
    from omegaconf import DictConfig
    cfg = DictConfig(yaml.safe_load(open("configs/v2/vc_wrapper.yaml", "r")))
    vc_wrapper = instantiate(cfg)
    vc_wrapper.load_checkpoints()
    vc_wrapper.to(device)
    vc_wrapper.eval()

    vc_wrapper.setup_ar_caches(max_batch_size=1, max_seq_len=4096, dtype=dtype, device=device)

    if args.compile:
        print("Compiling model with torch.compile...")
        torch._inductor.config.coordinate_descent_tuning = True
        torch._inductor.config.triton.unique_kernel_names = True

        if hasattr(torch._inductor.config, "fx_graph_cache"):
            # Experimental feature to reduce compilation times, will be on by default in future
            torch._inductor.config.fx_graph_cache = True
        vc_wrapper.compile_ar()
        # vc_wrapper.compile_cfm()

    return vc_wrapper


# Wrapper functions for GPU decoration
def convert_voice_v1_wrapper(source_audio_path, target_audio_path, diffusion_steps=10,
                             length_adjust=1.0, inference_cfg_rate=0.7, f0_condition=False,
                             auto_f0_adjust=True, pitch_shift=0, stream_output=True):
    """
    Wrapper function for vc_wrapper.convert_voice that can be decorated with @spaces.GPU
    """
    global vc_wrapper_v1
    from seed_vc_wrapper import SeedVCWrapper
    if vc_wrapper_v1 is None:
        vc_wrapper_v1 = SeedVCWrapper()

    # Use yield from to properly handle the generator
    yield from vc_wrapper_v1.convert_voice(
        source=source_audio_path,
        target=target_audio_path,
        diffusion_steps=diffusion_steps,
        length_adjust=length_adjust,
        inference_cfg_rate=inference_cfg_rate,
        f0_condition=f0_condition,
        auto_f0_adjust=auto_f0_adjust,
        pitch_shift=pitch_shift,
        stream_output=stream_output
    )


def convert_voice_v2_wrapper(source_audio_path, target_audio_path, diffusion_steps=30,
                             length_adjust=1.0, intelligebility_cfg_rate=0.7, similarity_cfg_rate=0.7,
                             top_p=0.7, temperature=0.7, repetition_penalty=1.5,
                             convert_style=False, anonymization_only=False, stream_output=True):
    """
    Wrapper function for vc_wrapper.convert_voice_with_streaming that can be decorated with @spaces.GPU
    """
    global vc_wrapper_v2

    # Use yield from to properly handle the generator
    yield from vc_wrapper_v2.convert_voice_with_streaming(
        source_audio_path=source_audio_path,
        target_audio_path=target_audio_path,
        diffusion_steps=diffusion_steps,
        length_adjust=length_adjust,
        intelligebility_cfg_rate=intelligebility_cfg_rate,
        similarity_cfg_rate=similarity_cfg_rate,
        top_p=top_p,
        temperature=temperature,
        repetition_penalty=repetition_penalty,
        convert_style=convert_style,
        anonymization_only=anonymization_only,
        device=device,
        dtype=dtype,
        stream_output=stream_output
    )


def create_v1_interface():
    # Set up Gradio interface
    description = (
        "Zero-shot voice conversion with in-context learning. For local deployment please check [GitHub repository](https://github.com/Plachtaa/seed-vc) "
        "for details and updates.<br>Note that any reference audio will be forcefully clipped to 25s if beyond this length.<br> "
        "If total duration of source and reference audio exceeds 30s, source audio will be processed in chunks.")

    inputs = [
        gr.Audio(type="filepath", label="Source Audio"),
        gr.Audio(type="filepath", label="Reference Audio"),
        gr.Slider(minimum=1, maximum=200, value=10, step=1, label="Diffusion Steps",
                  info="10 by default, 50~100 for best quality"),
        gr.Slider(minimum=0.5, maximum=2.0, step=0.1, value=1.0, label="Length Adjust",
                  info="<1.0 for speed-up speech, >1.0 for slow-down speech"),
        gr.Slider(minimum=0.0, maximum=1.0, step=0.1, value=0.7, label="Inference CFG Rate",
                  info="has subtle influence"),
        gr.Checkbox(label="Use F0 conditioned model", value=False,
                    info="Must be enabled for singing voice conversion"),
        gr.Checkbox(label="Auto F0 adjust", value=True,
                    info="Roughly adjust F0 to match the target voice. Only used when the F0 conditioned model is enabled."),
        gr.Slider(label='Pitch shift', minimum=-24, maximum=24, step=1, value=0,
                  info="Pitch shift in semitones, only used when the F0 conditioned model is enabled"),
    ]

    examples = [
        ["examples/source/yae_0.wav", "examples/reference/dingzhen_0.wav", 25, 1.0, 0.7, False, True, 0],
        ["examples/source/jay_0.wav", "examples/reference/azuma_0.wav", 25, 1.0, 0.7, True, True, 0],
        ["examples/source/Wiz Khalifa,Charlie Puth - See You Again [vocals]_[cut_28sec].wav",
         "examples/reference/teio_0.wav", 100, 1.0, 0.7, True, False, 0],
        ["examples/source/TECHNOPOLIS - 2085 [vocals]_[cut_14sec].wav",
         "examples/reference/trump_0.wav", 50, 1.0, 0.7, True, False, -12],
    ]

    outputs = [
        gr.Audio(label="Stream Output Audio", streaming=True, format='mp3'),
        gr.Audio(label="Full Output Audio", streaming=False, format='wav')
    ]

    return gr.Interface(
        fn=convert_voice_v1_wrapper,
        description=description,
        inputs=inputs,
        outputs=outputs,
        title="Seed Voice Conversion V1 (Voice & Singing Voice Conversion)",
        examples=examples,
        cache_examples=False,
    )


def create_v2_interface():
    # Set up Gradio interface
    description = (
        "Zero-shot voice/style conversion with in-context learning. For local deployment please check [GitHub repository](https://github.com/Plachtaa/seed-vc) "
        "for details and updates.<br>Note that any reference audio will be forcefully clipped to 25s if beyond this length.<br> "
        "If total duration of source and reference audio exceeds 30s, source audio will be processed in chunks.<br> "
        "Please click the 'convert style/emotion/accent' checkbox to convert the style, emotion, or accent of the source audio, or else only timbre conversion will be performed.<br> "
        "Click the 'anonymization only' checkbox will ignore reference audio but convert source to an 'average voice' determined by model itself.<br> "
        "Credits to [Vevo](https://github.com/open-mmlab/Amphion/tree/main/models/vc/vevo)"
        )
    inputs = [
        gr.Audio(type="filepath", label="Source Audio"),
        gr.Audio(type="filepath", label="Reference Audio"),
        gr.Slider(minimum=1, maximum=200, value=30, step=1, label="Diffusion Steps",
                  info="30 by default, 50~100 for best quality"),
        gr.Slider(minimum=0.5, maximum=2.0, step=0.1, value=1.0, label="Length Adjust",
                  info="<1.0 for speed-up speech, >1.0 for slow-down speech"),
        gr.Slider(minimum=0.0, maximum=1.0, step=0.1, value=0.0, label="Intelligibility CFG Rate",
                  info="controls pronunciation intelligibility"),
        gr.Slider(minimum=0.0, maximum=1.0, step=0.1, value=0.7, label="Similarity CFG Rate",
                  info="controls similarity to reference audio"),
        gr.Slider(minimum=0.1, maximum=1.0, step=0.1, value=0.9, label="Top-p",
                  info="AR model sampling top P"),
        gr.Slider(minimum=0.1, maximum=2.0, step=0.1, value=1.0, label="Temperature",
                  info="AR model sampling temperature"),
        gr.Slider(minimum=1.0, maximum=3.0, step=0.1, value=1.0, label="Repetition Penalty",
                  info="AR model sampling repetition penalty"),
        gr.Checkbox(label="convert style/emotion/accent", value=False),
        gr.Checkbox(label="anonymization only", value=False),
    ]

    examples = [
        ["examples/source/yae_0.wav", "examples/reference/dingzhen_0.wav", 50, 1.0, 0.0, 0.7, 0.9, 1.0, 1.0, False,
         False],
        ["examples/source/jay_0.wav", "examples/reference/azuma_0.wav", 50, 1.0, 0.0, 0.7, 0.9, 1.0, 1.0, False, False],
    ]

    outputs = [
        gr.Audio(label="Stream Output Audio", streaming=True, format='mp3'),
        gr.Audio(label="Full Output Audio", streaming=False, format='wav')
    ]

    return gr.Interface(
        fn=convert_voice_v2_wrapper,
        description=description,
        inputs=inputs,
        outputs=outputs,
        title="Seed Voice Conversion V2 (Voice & Style Conversion)",
        examples=examples,
        cache_examples=False,
    )


def main(args):
    global vc_wrapper_v1, vc_wrapper_v2
    # Create interfaces based on enabled versions
    interfaces = []

    # Load V2 models if enabled
    if args.enable_v2:
        print("Loading V2 models...")
        vc_wrapper_v2 = load_v2_models(args)
        v2_interface = create_v2_interface()
        interfaces.append(("V2 - Voice & Style Conversion", v2_interface))

    # Create V1 interface if enabled
    if args.enable_v1:
        print("Creating V1 interface...")
        v1_interface = create_v1_interface()
        interfaces.append(("V1 - Voice & Singing Voice Conversion", v1_interface))

    # Check if at least one version is enabled
    if not interfaces:
        print("Error: At least one version (V1 or V2) must be enabled.")
        return

    # Create tabs
    with gr.Blocks(title="Seed Voice Conversion") as demo:
        gr.Markdown("# Seed Voice Conversion")

        if len(interfaces) > 1:
            gr.Markdown("Choose between V1 (Voice & Singing Voice Conversion) or V2 (Voice & Style Conversion)")

            with gr.Tabs():
                for tab_name, interface in interfaces:
                    with gr.TabItem(tab_name):
                        interface.render()
        else:
            # If only one version is enabled, don't use tabs
            for _, interface in interfaces:
                interface.render()

    # Launch the combined interface
    demo.launch()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--compile", action="store_true", help="Compile the model using torch.compile")
    parser.add_argument("--enable-v1", action="store_true",
                        help="Enable V1 (Voice & Singing Voice Conversion)")
    parser.add_argument("--enable-v2", action="store_true",
                        help="Enable V2 (Voice & Style Conversion)")
    args = parser.parse_args()
    main(args)