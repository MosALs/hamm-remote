import 'package:flutter/material.dart';

import '../app/remote_controller.dart';
import '../protocol/keycodes.dart';
import 'theme.dart';

/// Types text into the search or text box that is selected on the TV.
Future<void> showTextInputSheet(BuildContext context, RemoteController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _TextInputSheet(controller: controller),
  );
}

class _TextInputSheet extends StatefulWidget {
  const _TextInputSheet({required this.controller});

  final RemoteController controller;

  @override
  State<_TextInputSheet> createState() => _TextInputSheetState();
}

class _TextInputSheetState extends State<_TextInputSheet> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Mirrors the phone field onto the TV field. Text edits replace the TV
  /// text; an empty field cannot be sent as text, so clear the last
  /// character with Delete instead.
  void _send() {
    final value = _text.text;
    if (value.isEmpty) {
      widget.controller.press(KeyCode.del);
    } else {
      widget.controller.sendText(value);
    }
  }

  void _deleteLast() {
    final value = _text.text;
    if (value.isEmpty) {
      widget.controller.press(KeyCode.del);
      return;
    }
    final characters = value.runes.toList()..removeLast();
    _text.text = String.fromCharCodes(characters);
    _send();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Type on the TV', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'Select a search or text box on the TV first. What you type here replaces its text.',
            style: TextStyle(color: Palette.muted, fontSize: 13.5),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            autofocus: true,
            textInputAction: TextInputAction.send,
            onChanged: (_) => _send(),
            onSubmitted: (_) => widget.controller.press(KeyCode.enter),
            decoration: const InputDecoration(hintText: 'Search or text…'),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _deleteLast,
                  icon: const Icon(Icons.backspace_outlined),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => widget.controller.press(KeyCode.enter),
                  icon: const Icon(Icons.keyboard_return_rounded),
                  label: const Text('Enter'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
