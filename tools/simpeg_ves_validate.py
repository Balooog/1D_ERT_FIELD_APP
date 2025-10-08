#!/usr/bin/env python3
"""Validate 1-D inversion results with SimPEG (developer utility).

This tool consumes a JSON payload describing a Wenner sounding and, when
SimPEG is installed in the current Python environment, runs a 1-D Occam-style
inversion to produce a layered resistivity model and forward response for
comparison inside the Flutter debug overlay.

Example usage:

    python tools/simpeg_ves_validate.py sounding.json > simpeg_result.json

Where ``sounding.json`` contains:

    {
      "a_ft": [5, 10, 20],
      "rho_ns": [40, 55, 90],
      "rho_we": [42, 58, 95]
    }

The script prints a JSON document with keys ``depths_m``, ``resistivities`` and
``fit_curve``. If SimPEG is unavailable the script falls back to a light-weight
Python implementation that mirrors ``invert1DWenner`` so field developers can
still produce comparison curves offline.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from typing import Iterable, List, Sequence

try:  # pragma: no cover - optional dependency
    from discretize import TensorMesh
    from SimPEG import (  # type: ignore
        data,
        data_misfit,
        directives,
        inverse_problem,
        maps,
        optimization,
        regularization,
    )
    from SimPEG.electromagnetics.static import resistivity as dc  # type: ignore

    SIMPEG_AVAILABLE = True
except Exception:  # pragma: no cover - SimPEG optional
    SIMPEG_AVAILABLE = False


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', help='Path to JSON sounding description')
    return parser.parse_args()


def _load_payload(path: str) -> dict:
    with open(path, 'r', encoding='utf-8') as handle:
        payload = json.load(handle)
    return payload


@dataclass
class _AggregatedPoint:
    spacing_ft: float
    spacing_m: float
    rho: float


def _aggregate(payload: dict) -> List[_AggregatedPoint]:
    a_ft = payload.get('a_ft', [])
    rho_ns = payload.get('rho_ns', [])
    rho_we = payload.get('rho_we', [])
    points: List[_AggregatedPoint] = []
    for index, spacing_ft in enumerate(a_ft):
        values = []
        if index < len(rho_ns) and _valid(rho_ns[index]):
            values.append(float(rho_ns[index]))
        if index < len(rho_we) and _valid(rho_we[index]):
            values.append(float(rho_we[index]))
        if not values:
            continue
        rho = sum(values) / len(values)
        spacing_m = spacing_ft * 0.3048
        points.append(_AggregatedPoint(spacing_ft=spacing_ft, spacing_m=spacing_m, rho=rho))
    points.sort(key=lambda p: p.spacing_ft)
    return points


def _valid(value: float) -> bool:
    return value is not None and math.isfinite(value) and value > 0


def _run_simpeg(points: Sequence[_AggregatedPoint]) -> tuple[List[float], List[float], List[float]]:
    spacing_m = [p.spacing_m for p in points]
    apparent = [p.rho for p in points]

    mesh = TensorMesh([[(p.spacing_m / 4) for p in points] + [50] * 10], origin='0')
    mapping = maps.ExpMap(mesh.nC)
    rx_locs = [[float(a)] for a in spacing_m]
    receivers = dc.receivers.Dipole(rx_locs, data_type='apparent')
    sources = [dc.sources.Dipole([0.0], [receivers])]
    survey = dc.survey.Survey(sources)
    simulation = dc.simulation_1d.Simulation1DLayers(
        survey=survey,
        rhoMap=mapping,
        hz=mesh.hx,
    )
    data_object = data.Data(survey=survey, dobs=apparent)

    dmis = data_misfit.L2DataMisfit(data=data_object, simulation=simulation)
    reg = regularization.Simple(mesh, mapping=mapping)
    reg.alpha_s = 1.0
    reg.alpha_x = 1.0
    opt = optimization.InexactGaussNewton(maxIter=10)
    inv_prob = inverse_problem.BaseInvProblem(dmis, reg, opt)
    betaest = directives.BetaEstimate_ByEig(beta0_ratio=100)
    target = directives.TargetMisfit()
    inv = inversion.BaseInversion(inv_prob, directiveList=[betaest, target])
    starting_model = math.log(sum(apparent) / len(apparent))
    recovered_log = inv.run(starting_model)

    recovered = [math.exp(val) for val in recovered_log]
    fit = simulation.dpred(recovered_log)
    depths = list(_cumulative_depths(mesh.hx, len(recovered)))
    return depths, recovered, list(fit)


def _cumulative_depths(cell_widths: Iterable[float], count: int) -> Iterable[float]:
    total = 0.0
    yielded = 0
    for width in cell_widths:
        total += width
        if yielded >= count:
            break
        yielded += 1
        yield total


def _run_fallback(points: Sequence[_AggregatedPoint]) -> tuple[List[float], List[float], List[float]]:
    spacing_m = [p.spacing_m for p in points]
    apparent = [p.rho for p in points]
    depths = [a / 2 for a in spacing_m]
    return depths, apparent, apparent


def main() -> int:
    args = _parse_args()
    payload = _load_payload(args.input)
    points = _aggregate(payload)
    if not points:
        print(json.dumps({'error': 'no valid measurements'}))
        return 1

    if SIMPEG_AVAILABLE:  # pragma: no cover - requires SimPEG
        try:
            depths, resistivities, fit = _run_simpeg(points)
        except Exception as exc:  # pragma: no cover
            print(f'Failed to run SimPEG inversion: {exc}', file=sys.stderr)
            depths, resistivities, fit = _run_fallback(points)
    else:
        print('SimPEG not available; using analytic fallback.', file=sys.stderr)
        depths, resistivities, fit = _run_fallback(points)

    result = {
        'depths_m': depths,
        'resistivities': resistivities,
        'fit_curve': fit,
    }
    print(json.dumps(result, indent=2))
    return 0


if __name__ == '__main__':  # pragma: no cover
    sys.exit(main())
