import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_surface.dart';

/// Burbuja de mensaje. La del usuario va alineada a la derecha con el color
/// primario; la del asistente a la izquierda sobre la superficie del tema.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
    this.isStreaming = false,
    this.fromPhone = false,
  });

  final String text;
  final bool isUser;
  final bool isStreaming;

  /// Dibuja un icono de telefono minusculo delante del texto.
  final bool fromPhone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        // Una burbuja a todo el ancho de un dialogo de 900 px es ilegible: la
        // vista salta de renglon en renglon.
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: isUser ? scheme.primary : scheme.surfaceContainer,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(AppRadius.chip),
              topRight: const Radius.circular(AppRadius.chip),
              bottomLeft: Radius.circular(isUser ? AppRadius.chip : AppSpacing.xs),
              bottomRight: Radius.circular(isUser ? AppSpacing.xs : AppRadius.chip),
            ),
            border: isUser ? null : Border.fromBorderSide(AppSurface.hairline(scheme)),
          ),
          child: fromPhone
              ? _withPhoneBadge(theme, scheme)
              : _buildText(theme, scheme),
        ),
      ),
    );
  }

  /// El distintivo del telefono: un icono chico delante del texto, del mismo
  /// color que la burbuja pero atenuado.
  ///
  /// Va **dentro** del parrafo y no como fila aparte a proposito. Una fila
  /// propia sumaria alto a cada mensaje del telefono y desalinearia la
  /// conversacion; asi ocupa lo que ocupa una palabra y se lee como parte del
  /// mensaje. Por lo mismo no lleva texto: "desde el movil" repetido en cada
  /// burbuja seria ruido, y el icono ya lo dice.
  Widget _withPhoneBadge(ThemeData theme, ColorScheme scheme) {
    final color = isUser ? scheme.onPrimary : scheme.onSurface;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: Icon(
                Icons.smartphone,
                size: 13,
                color: color.withValues(alpha: 0.55),
              ),
            ),
          ),
          TextSpan(text: text),
        ],
      ),
      style: theme.textTheme.bodyMedium?.copyWith(color: color, height: 1.42),
    );
  }

  /// Mientras el mensaje se esta escribiendo, el texto cambia cada 15-30 ms
  /// (a 39 tok/s): parsear markdown en cada redibujo (y reconstruir el
  /// arbol de widgets que arma) es un costo que no aporta nada hasta que el
  /// mensaje termina de llegar, y reintroduciria el mismo tipo de tosquedad
  /// que costo arreglar el scroll. Por eso durante el streaming se sigue
  /// con `Text.rich` plano, y el markdown (`MarkdownBody`) se dibuja recien
  /// cuando `isStreaming` se apaga — que es ademas el unico momento en que
  /// vale la pena: a mitad de un `**` sin cerrar no hay nada que renderizar.
  Widget _buildText(ThemeData theme, ColorScheme scheme) {
    final color = isUser ? scheme.onPrimary : scheme.onSurface;

    if (isStreaming) {
      return Text.rich(
        TextSpan(
          text: text,
          children: [
            // Cursor de escritura. Va como span y no como widget aparte
            // para que quede pegado a la ultima palabra en vez de saltar a
            // la linea siguiente.
            TextSpan(text: ' ▍', style: TextStyle(color: color.withValues(alpha: 0.45))),
          ],
        ),
        style: theme.textTheme.bodyMedium?.copyWith(color: color, height: 1.42),
      );
    }

    final body = theme.textTheme.bodyMedium?.copyWith(color: color, height: 1.42);
    final codeColor = isUser ? scheme.onPrimary : scheme.onSurface;
    final codeBackground = (isUser ? scheme.onPrimary : scheme.onSurface).withValues(alpha: 0.12);

    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: body,
        strong: body?.copyWith(fontWeight: FontWeight.w700),
        em: body?.copyWith(fontStyle: FontStyle.italic),
        listBullet: body,
        blockquote: body?.copyWith(color: color.withValues(alpha: 0.75)),
        h1: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
        h2: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
        h3: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
        a: body?.copyWith(color: scheme.primary, decoration: TextDecoration.underline),
        code: body?.copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Consolas', 'Menlo', 'monospace'],
          backgroundColor: codeBackground,
          color: codeColor,
        ),
        codeblockDecoration: BoxDecoration(
          color: codeBackground,
          borderRadius: BorderRadius.circular(AppSpacing.xs),
        ),
        codeblockPadding: const EdgeInsets.all(AppSpacing.sm),
        blockSpacing: AppSpacing.sm,
        // Los margenes por defecto de flutter_markdown asumen una pagina
        // entera: adentro de una burbuja angosta dejaban un hueco enorme
        // antes del primer parrafo y despues del ultimo.
        pPadding: EdgeInsets.zero,
      ),
    );
  }
}
