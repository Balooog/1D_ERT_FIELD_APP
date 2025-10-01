enum ArrayType { wenner, schlumberger, dipoleDipole, poleDipole, custom }

extension ArrayTypeLabels on ArrayType {
  String get label {
    switch (this) {
      case ArrayType.wenner:
        return 'Wenner';
      case ArrayType.schlumberger:
        return 'Schlumberger';
      case ArrayType.dipoleDipole:
        return 'Dipole-Dipole';
      case ArrayType.poleDipole:
        return 'Pole-Dipole';
      case ArrayType.custom:
        return 'Custom';
    }
  }
}
