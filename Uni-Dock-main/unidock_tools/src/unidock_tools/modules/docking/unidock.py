from typing import List, Tuple, Dict, Optional
from pathlib import Path
import logging
import os
import platform
import shutil
import subprocess
import sys

from unidock_tools.utils import randstr, time_logger
from .gen_grid import generate_ad4_grid


def _find_unidock_binary() -> str:
    """Locate the unidock executable across platforms.

    Search order:
    1. PATH (shutil.which) — honours conda environments and pip installs
    2. Same directory as this Python interpreter (common in editable installs)
    3. Bundled binary shipped next to this module (./bin/)

    Returns the resolved path string, or raises FileNotFoundError.
    """
    bin_name = "unidock.exe" if platform.system() == "Windows" else "unidock"

    # 1. PATH lookup
    found = shutil.which(bin_name)
    if found:
        return found

    # 2. Next to the Python executable (conda / venv installs)
    py_bin_dir = Path(sys.executable).parent
    candidate = py_bin_dir / bin_name
    if candidate.is_file():
        return str(candidate)

    # 3. Bundled ./bin/ directory relative to this module
    bundled = Path(__file__).parent / "bin" / bin_name
    if bundled.is_file():
        return str(bundled)

    raise FileNotFoundError(
        f"Uni-Dock binary '{bin_name}' not found.\n"
        f"  Linux/Windows: install via  conda install unidock -c conda-forge\n"
        f"    or build from source and add to PATH.\n"
        f"  macOS (Apple Silicon): CUDA is not supported; GPU docking unavailable.\n"
        f"    You can build the CPU-only version with  cmake -DFORCE_CPU_ONLY=ON ."
    )


class UniDockRunner:
    def __init__(self,
                 receptor: Path,
                 ligands: List[Path],
                 output_dir: Path,
                 center_x: float,
                 center_y: float,
                 center_z: float,
                 size_x: float = 22.5,
                 size_y: float = 22.5,
                 size_z: float = 22.5,
                 scoring: str = "vina",
                 num_modes: int = 10,
                 search_mode: str = "",
                 exhaustiveness: int = 256,
                 max_step: int = 10,
                 energy_range: float = 3.0,
                 refine_step: int = 5,
                 bias_file: Optional[Path] = None,
                 seed : int = 181129,
                 score_only: bool = False,
                 local_only: bool = False,
                 multi_bias: bool = False,
                 ):

        self.workdir = output_dir / f"unidock_{randstr()}"
        os.makedirs(self.workdir, exist_ok=True)
        cmd = [_find_unidock_binary()]

        if score_only:
            size_x = min(size_x*2, 25)
            size_y = min(size_y*2, 25)
            size_z = min(size_z*2, 25)

        if scoring.lower() == "ad4":
            map_dir = os.path.join(self.workdir, "mapdir")
            os.makedirs(map_dir, exist_ok=True)
            map_prefix = generate_ad4_grid(str(receptor), map_dir, 
                                           (center_x, center_y, center_z), 
                                           (size_x, size_y, size_z))
            cmd += ["--maps", map_prefix]
        else:
            cmd += ["--receptor", str(receptor)]

        ligand_index_path = os.path.join(self.workdir, f"ligand_index_{randstr()}.txt")
        with open(ligand_index_path, "w") as f:
            f.write("\n".join([str(ligand) for ligand in ligands]))
        cmd += ["--ligand_index", ligand_index_path]

        if not output_dir:
            output_dir = os.path.join(self.workdir, "results_dir")
        cmd += ["--dir", str(output_dir)]

        if search_mode:
            cmd += ["--search_mode", search_mode]
        else:
            cmd += [
                "--exhaustiveness", str(exhaustiveness),
                "--max_step", str(max_step),
            ]

        cmd += [
            "--center_x", str(center_x),
            "--center_y", str(center_y),
            "--center_z", str(center_z),
            "--size_x", str(size_x),
            "--size_y", str(size_y),
            "--size_z", str(size_z),
            "--scoring", scoring,
            "--num_modes", str(num_modes),
            "--energy_range", str(energy_range),
            "--refine_step", str(refine_step),
            "--seed", str(seed),
            "--verbosity", "2",
            "--keep_nonpolar_H",
        ]
        if bias_file:
            cmd += ["--bias", str(bias_file)]
        if score_only:
            cmd.append("--score_only")
        if local_only:
            cmd.append("--local_only")
        if multi_bias:
            cmd.append("--multi_bias")

        logging.info(f"unidock cmd: {' '.join(cmd)}")
        self.cmd = cmd

        self.pre_result_ligands = [Path(os.path.join(output_dir, f"{l.stem}_out.sdf")) for l in ligands]

    def run(self):
        # Use locale-aware encoding on Windows (may be cp936/gbk);
        # UTF-8 is safe on Linux and macOS.
        _enc = "utf-8" if platform.system() != "Windows" else None
        resp = subprocess.run(
            self.cmd,
            capture_output=True,
            encoding=_enc,
            errors="replace",
        )
        if _enc is None and isinstance(resp.stdout, bytes):
            resp_stdout = resp.stdout.decode(errors="replace")
            resp_stderr = resp.stderr.decode(errors="replace")
        else:
            resp_stdout = resp.stdout or ""
            resp_stderr = resp.stderr or ""
        logging.debug(f"Run Uni-Dock log: {resp_stdout}")
        if resp.returncode != 0:
            logging.info(f"Run Uni-Dock log\n{resp_stdout}")
            logging.error(f"Run Uni-Dock error\n{resp_stderr}")

        result_ligands = [f for f in self.pre_result_ligands if os.path.exists(f)]
        return result_ligands

    @staticmethod
    def read_scores(ligand_file: Path) -> List[float]:
        score_list = []
        with open(ligand_file, "r") as f:
            lines = f.readlines()
            for idx, line in enumerate(lines):
                if line.startswith("> <Uni-Dock RESULT>"):
                    score = float(lines[idx + 1].partition(
                        "LOWER_BOUND=")[0][len("ENERGY="):])
                    score_list.append(score)
        return score_list

    @staticmethod
    def read_score_txt(txt_file: Path) -> Dict[str, float]:
        """Read scores.txt file which is generated by Uni-Dock score_only mode and get score value.

        Args:
            txt_file (Path): scores.txt file

        Returns:
            List[Tuple[str, float]]: List of (file_base, score) tuples
        """
        file_score_dict = dict()
        with open(txt_file, "r") as f:
            for line in f.readlines():
                if line.startswith("REMARK"):
                    line_list = line.strip().split(" ")
                    file_base = line_list[1]
                    score = float(line_list[2])
                    file_score_dict[file_base] = score
        return file_score_dict

    def clean_workdir(self):
        shutil.rmtree(self.workdir, ignore_errors=True)


@time_logger
def run_unidock(
        receptor: Path,
        ligands: List[Path],
        output_dir: Path,
        center_x: float,
        center_y: float,
        center_z: float,
        size_x: float = 22.5,
        size_y: float = 22.5,
        size_z: float = 22.5,
        scoring: str = "vina",
        num_modes: int = 10,
        search_mode: str = "",
        exhaustiveness: int = 256,
        max_step: int = 10,
        energy_range: float = 3.0,
        refine_step: int = 5,
        bias_file: Optional[Path] = None,
        seed: int = 181129,
        score_only: bool = False,
        local_only: bool = False,
        multi_bias: bool = False,
        debug: bool = False,
) -> Tuple[List[Path], List[List[float]]]:
    runner = UniDockRunner(
        receptor=receptor, ligands=ligands, output_dir=output_dir,
        center_x=center_x, center_y=center_y, center_z=center_z,
        size_x=size_x, size_y=size_y, size_z=size_z,
        scoring=scoring, num_modes=num_modes,
        search_mode=search_mode,
        exhaustiveness=exhaustiveness, max_step=max_step,
        energy_range=energy_range, refine_step=refine_step, seed=seed, bias_file=bias_file,
        score_only=score_only, local_only=local_only, multi_bias=multi_bias,
    )
    result_ligands = runner.run()
    scores_list = [UniDockRunner.read_scores(ligand) for ligand in result_ligands]
    if score_only:
        scores_txt = output_dir / "scores.txt"
        filename_score_dict = UniDockRunner.read_score_txt(scores_txt)
        result_ligands = ligands
        scores_list = [[filename_score_dict[os.path.basename(fpath)]] for fpath in result_ligands]
    
    if not debug:
        runner.clean_workdir()

    return result_ligands, scores_list
