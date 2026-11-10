"""Recreate the three Chapter 3 figures (all eight operations) from CPU benchmark results.

Examples:
    python plot_chapter3.py --input cpu_results_results_article.zip
    python plot_chapter3.py --input results_article --output figures_check
"""
import argparse
from pathlib import Path
from zipfile import ZipFile
import io

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def load_conditions(source: Path) -> pd.DataFrame:
    if source.is_dir():
        path = source / 'condition_summary.csv'
        if not path.is_file():
            raise FileNotFoundError(f'Could not find {path}')
        return pd.read_csv(path, encoding='utf-8-sig')
    if source.suffix.lower() == '.zip':
        with ZipFile(source) as archive:
            match = next((name for name in archive.namelist()
                          if name == 'condition_summary.csv' or name.endswith('/condition_summary.csv')), None)
            if match is None:
                raise FileNotFoundError('condition_summary.csv is missing in the ZIP')
            return pd.read_csv(io.BytesIO(archive.read(match)), encoding='utf-8-sig')
    return pd.read_csv(source, encoding='utf-8-sig')


def main():
    parser = argparse.ArgumentParser(description='Regenerate Chapter 3 CPU benchmark charts')
    parser.add_argument('--input', default='cpu_results_results_article.zip',
                        help='Results ZIP, results directory, or condition_summary.csv')
    parser.add_argument('--output', default='figures_check', help='Directory for three generated PNG files')
    args = parser.parse_args()
    source = Path(args.input)
    out = Path(args.output)
    if not source.exists():
        parser.error(f'Results not found: {source}')
    out.mkdir(parents=True, exist_ok=True)
    c = load_conditions(source)
    expected = ['environment', 'test', 'count', 'mean_session_wall_sec', 'mean_cpu_wall_ratio']
    missing = [key for key in expected if key not in c]
    if missing:
        parser.error(f'Missing columns: {missing}')
    idx = c.set_index(['environment', 'test', 'count'])
    counts = [1, 8, 16, 24, 32]
    ops = ['int_add', 'int_sub', 'int_mul', 'int_div',
           'double_add', 'double_sub', 'double_mul', 'double_div']

    def get(environment, test, count, key='mean_session_wall_sec'):
        return float(idx.loc[(environment, test, count), key])

    def relative(test, environment, count):
        return get(environment, test, count) / get(environment, test, 1) * 100

    plt.rcParams['font.family'] = 'DejaVu Sans'
    plt.rcParams['axes.titlesize'] = 13
    plt.rcParams['axes.labelsize'] = 11
    plt.rcParams['legend.fontsize'] = 9

    def relative_figure(filename, prefix):
        """Four panels, one per operation; both environments shown in each panel."""
        fig, axes = plt.subplots(2, 2, figsize=(9.4, 7.2), sharex=True, sharey=True)
        titles = {'add': 'Сложение', 'sub': 'Вычитание',
                  'mul': 'Умножение', 'div': 'Деление'}
        for ax, suffix in zip(axes.flat, ['add', 'sub', 'mul', 'div']):
            op = f'{prefix}_{suffix}'
            for env, style in [('Windows', '-'), ('Docker', '--')]:
                values = [relative(op, env, k) for k in counts]
                ax.plot(counts, values, marker='o', linestyle=style,
                        markersize=5, linewidth=2, label=env)
            ax.axhline(100, color='gray', linewidth=1, linestyle=':')
            ax.set_title(titles[suffix])
            ax.set_xticks(counts)
            ax.tick_params(labelbottom=True)
            ax.grid(axis='y', alpha=0.28)
            ax.set_ylim(bottom=0)
        handles, labels = axes[0, 0].get_legend_handles_labels()
        fig.legend(handles, labels, ncol=2, loc='upper center',
                   bbox_to_anchor=(0.5, 0.995), frameon=True)
        fig.supylabel('Относительное время, %', fontsize=12)
        fig.supxlabel('Количество одновременно работающих экземпляров', fontsize=12)
        fig.tight_layout(rect=(0.04, 0.05, 0.995, 0.93))
        fig.savefig(out / filename, dpi=200)
        plt.close(fig)

    relative_figure('ch3_int_relative.png', 'int')
    relative_figure('ch3_double_relative.png', 'double')

    fig, ax = plt.subplots(figsize=(8.1, 4.35))
    x = np.arange(len(ops))
    windows = np.array([get('Windows', t, 32, 'mean_cpu_wall_ratio') * 100 for t in ops])
    docker = np.array([get('Docker', t, 32, 'mean_cpu_wall_ratio') * 100 for t in ops])
    ax.bar(x - 0.19, windows, width=0.38, label='Windows')
    ax.bar(x + 0.19, docker, width=0.38, label='Docker')
    ax.set_xticks(x, [t.replace('double_', 'd_').replace('int_', 'i_') for t in ops], rotation=20)
    ax.set_ylim(0, 85)
    ax.set_ylabel('CPU time / wall time, %')
    ax.set_xlabel('Арифметический тест')
    ax.grid(axis='y', alpha=0.3)
    ax.legend(loc='upper right')
    fig.tight_layout()
    fig.savefig(out / 'ch3_cpu_ratio.png', dpi=190)
    plt.close(fig)

    for name in ['ch3_int_relative.png', 'ch3_double_relative.png', 'ch3_cpu_ratio.png']:
        print(f'Saved: {out / name}')


if __name__ == '__main__':
    main()
