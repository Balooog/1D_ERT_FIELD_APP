import 'package:flutter/material.dart';

import 'sizing.dart';

InputDecoration resFieldDecoration([String hint = '']) => InputDecoration(
      isDense: true,
      hintText: hint,
      constraints: const BoxConstraints.tightFor(height: kFieldH),
      contentPadding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      border: kFieldBorder,
      enabledBorder: kFieldBorder,
      focusedBorder: kFieldBorder,
      disabledBorder: kFieldBorder,
      prefixIconConstraints: const BoxConstraints.tightFor(height: kFieldH),
      suffixIconConstraints: const BoxConstraints.tightFor(height: kFieldH),
    );
