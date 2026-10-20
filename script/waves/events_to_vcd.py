"""Convert the sparse full-system FreeRTOS event trace to a standard VCD."""

import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'build' / 'rtos' / 'rtos_events.csv'
TARGET = ROOT / 'build' / 'waves' / 'rtos_system_events.vcd'
FIELDS = [
    ('reset', 1, False), ('rx', 1, False), ('tx', 1, False),
    ('timer_irq', 1, False), ('software_irq', 1, False),
    ('external_irq', 1, False), ('lines', 32, True),
    ('timer_edges', 32, True), ('software_edges', 32, True),
    ('external_edges', 32, True), ('pending', 2, False),
    ('claimed', 2, False),
]


def main():
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    with SOURCE.open(newline='') as source, TARGET.open('w', newline='\n') as target:
        reader = csv.DictReader(source)
        names = [field for field, _, _ in FIELDS]
        if reader.fieldnames != ['time_ps', *names]:
            raise ValueError('RTOS event trace schema mismatch')
        target.write('$timescale 1ps $end\n$scope module tb_rtos $end\n')
        for index, (field, width, _) in enumerate(FIELDS):
            target.write(f'$var wire {width} {chr(33 + index)} {field} $end\n')
        target.write('$upscope $end\n$enddefinitions $end\n')
        previous = {}
        previous_time = -1
        count = 0
        for row in reader:
            time = int(row['time_ps'])
            if time < previous_time:
                raise ValueError('RTOS event times are not monotonic')
            changes = []
            for index, (field, width, decimal) in enumerate(FIELDS):
                value = row[field]
                if decimal:
                    value = format(int(value), f'0{width}b')
                elif len(value) != width or any(bit not in '01xz' for bit in value):
                    raise ValueError(f'Invalid {field} value at {time}: {value!r}')
                if previous.get(field) != value:
                    symbol = chr(33 + index)
                    changes.append(f'{value}{symbol}' if width == 1
                                   else f'b{value} {symbol}')
                    previous[field] = value
            if changes:
                target.write(f'#{time}\n' + '\n'.join(changes) + '\n')
            previous_time = time
            count += 1
    if count == 0 or previous_time < 70_000_000_000:
        TARGET.unlink(missing_ok=True)
        raise ValueError('RTOS event trace is incomplete')
    print(f'{TARGET}: {count} event records, ending at {previous_time} ps')


if __name__ == '__main__':
    main()
