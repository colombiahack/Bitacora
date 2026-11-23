import 'package:flutter/material.dart';

import 'certificate_page.dart';
import 'checklists_page.dart';
import 'documents_page.dart';
import 'export_page.dart';
import 'incidents_page.dart';
import 'maintenance_page.dart';
import 'stats_page.dart';
import 'update_ui.dart';
import '../../../core/services/update_service.dart';

/// Pestaña "Más": acceso a las herramientas adicionales.
class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  Widget _tile(BuildContext context, IconData icon, String title, String subtitle,
      Widget page) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => page),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Más herramientas')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tile(context, Icons.build_circle_outlined, 'Mantenimiento',
              'Tareas programadas por horas o días', const MaintenancePage()),
          _tile(context, Icons.description_outlined, 'Documentos',
              'Seguros, licencias y permisos con vencimiento', const DocumentsPage()),
          _tile(context, Icons.report_problem_outlined, 'Incidentes',
              'Registro de novedades de seguridad', const IncidentsPage()),
          _tile(context, Icons.checklist_rtl, 'Checklists',
              'Edita tus listas de verificación', const ChecklistsPage()),
          _tile(context, Icons.verified_outlined, 'Certificar horas',
              'Autodeclaración de horas en PDF para firmar', const CertificatePage()),
          _tile(context, Icons.bar_chart, 'Estadísticas',
              'Gráficos de horas y vuelos', const StatsPage()),
          _tile(context, Icons.ios_share, 'Exportar y respaldo',
              'CSV y copia de seguridad de tus datos', const ExportPage()),
          Card(
            child: ListTile(
              leading: const Icon(Icons.system_update),
              title: const Text('Buscar actualizaciones'),
              subtitle: Text(UpdateService.currentBuild == 0
                  ? 'Versión local'
                  : 'Versión ${UpdateService.currentBuild}'),
              onTap: () => checkForUpdates(context),
            ),
          ),
        ],
      ),
    );
  }
}
