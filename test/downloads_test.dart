import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlv_panel/downloads.dart';

void main() {
  group('DownloadStore.sanitizeFileName', () {
    test('remove caracteres inválidos de nomes de arquivo', () {
      expect(
        DownloadStore.sanitizeFileName(r'a/b\c:d*e?f"g<h>i|j'),
        'a_b_c_d_e_f_g_h_i_j',
      );
    });

    test('usa nome padrão quando o nome fica vazio', () {
      expect(DownloadStore.sanitizeFileName('   '), 'download');
    });

    test('limita o nome a 120 caracteres', () {
      final long = 'a' * 300;
      final result = DownloadStore.sanitizeFileName(long);
      expect(result.length, 120);
      expect(result, 'a' * 120);
    });

    test('mantém caracteres acentuados', () {
      expect(
        DownloadStore.sanitizeFileName('dados-Brasil-2024.xlsx'),
        'dados-Brasil-2024.xlsx',
      );
    });
  });

  group('formatFileSize', () {
    test('formata bytes, kB e MB', () {
      expect(formatFileSize(500), '500 B');
      expect(formatFileSize(2048), '2.0 kB');
      expect(formatFileSize(5 * 1024 * 1024), '5.0 MB');
    });
  });

  group('iconForFile', () {
    test('retorna ícone conforme a extensão', () {
      expect(iconForFile('/tmp/Brasil.xlsx'), Icons.grid_on);
      expect(iconForFile('/tmp/serie.csv'), Icons.table_chart);
      expect(iconForFile('/tmp/codigo.zip'), Icons.folder_zip);
      expect(iconForFile('/tmp/outro.bin'), Icons.insert_drive_file);
    });
  });
}
