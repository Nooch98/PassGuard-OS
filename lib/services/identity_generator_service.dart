import 'dart:math';

enum GeneratorCountry { usa, spain, mexico, uk }

class IdentityGeneratorService {
  static final Random _random = Random();

  static const Map<GeneratorCountry, Map<String, dynamic>> _localizedData = {
    GeneratorCountry.usa: {
      'countryName': 'United States',
      'firstNames': ['James', 'Mary', 'John', 'Patricia', 'Robert', 'Jennifer', 'Michael', 'Linda', 'William', 'Elizabeth'],
      'lastNames': ['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Miller', 'Davis', 'Wilson', 'Anderson', 'Taylor'],
      'cities': ['Springfield', 'Franklin', 'Clinton', 'Georgetown', 'Madison', 'Washington', 'Austin', 'Seattle'],
      'states': ['California', 'Texas', 'Florida', 'New York', 'Illinois', 'Ohio', 'Georgia', 'Washington'],
      'streets': ['Main', 'Oak', 'Pine', 'Maple', 'Cedar', 'Elm', 'Washington', 'Lake'],
      'streetTypes': ['St', 'Ave', 'Blvd', 'Rd', 'Lane'],
      'phonePrefix': '+1',
      'zipFormat': '#####',
    },
    GeneratorCountry.spain: {
      'countryName': 'Spain',
      'firstNames': ['Antonio', 'María', 'Manuel', 'Jose', 'Francisco', 'David', 'Juan', 'Javier', 'Elena', 'Lucía'],
      'lastNames': ['García', 'Rodríguez', 'González', 'Fernández', 'López', 'Martínez', 'Sánchez', 'Pérez', 'Gómez'],
      'cities': ['Madrid', 'Barcelona', 'Valencia', 'Sevilla', 'Zaragoza', 'Málaga', 'Murcia', 'Bilbao'],
      'states': ['Madrid', 'Cataluña', 'Andalucía', 'Comunidad Valenciana', 'Galicia', 'Castilla y León'],
      'streets': ['Mayor', 'Real', 'Constitución', 'Princesa', 'Gran Vía', 'Castellana', 'Colon'],
      'streetTypes': ['Calle', 'Avenida', 'Paseo', 'Plaza', 'Ronda'],
      'phonePrefix': '+34',
      'zipFormat': '28###',
    },
    GeneratorCountry.mexico: {
      'countryName': 'Mexico',
      'firstNames': ['José', 'María', 'Guadalupe', 'Alejandro', 'Miguel Angel', 'Ximena', 'Diego', 'Sofía', 'Mateo'],
      'lastNames': ['Hernández', 'García', 'Martínez', 'López', 'González', 'Pérez', 'Rodríguez', 'Sánchez'],
      'cities': ['CDMX', 'Guadalajara', 'Monterrey', 'Puebla', 'Querétaro', 'Tijuana', 'León', 'Mérida'],
      'states': ['Jalisco', 'Nuevo León', 'Estado de México', 'Yucatán', 'Puebla', 'Guanajuato', 'Veracruz'],
      'streets': ['Reforma', 'Juárez', 'Independencia', 'Hidalgo', 'Insurgentes', '5 de Mayo'],
      'streetTypes': ['Calle', 'Avenida', 'Calzada', 'Privada', 'Bulevar'],
      'phonePrefix': '+52',
      'zipFormat': '#####',
    },
    GeneratorCountry.uk: {
      'countryName': 'United Kingdom',
      'firstNames': ['Oliver', 'Olivia', 'George', 'Amelia', 'Harry', 'Isla', 'Noah', 'Ava', 'Leo', 'Mia'],
      'lastNames': ['Smith', 'Jones', 'Taylor', 'Brown', 'Williams', 'Wilson', 'Johnson', 'Davies', 'Robinson'],
      'cities': ['London', 'Manchester', 'Birmingham', 'Leeds', 'Glasgow', 'Liverpool', 'Bristol', 'Sheffield'],
      'states': ['England', 'Scotland', 'Wales', 'Northern Ireland', 'Greater London', 'West Midlands'],
      'streets': ['High St', 'Station Rd', 'Main St', 'Park Rd', 'Church Rd', 'London Rd', 'Victoria Rd'],
      'streetTypes': ['St', 'Rd', 'Lane', 'Close', 'Way', 'Gardens'],
      'phonePrefix': '+44',
      'zipFormat': '??# #??', 
    },
  };

  static const List<String> _emailDomains = [
    'gmail.com', 'yahoo.com', 'outlook.com', 'hotmail.com', 'protonmail.com', 'icloud.com'
  ];

  static Map<String, String> generatePersonIdentity({GeneratorCountry country = GeneratorCountry.usa}) {
    final data = _localizedData[country]!;
    
    final firstName = _getRandom(data['firstNames']);
    final lastName = _getRandom(data['lastNames']);
    final fullName = '$firstName $lastName';

    final emailPrefix = '${firstName.toLowerCase().replaceAll(' ', '')}.${lastName.toLowerCase()}${_random.nextInt(999)}';
    final email = '$emailPrefix@${_getRandom(_emailDomains)}';

    String phone = '${data['phonePrefix']} ';
    if (country == GeneratorCountry.usa) phone += '${_randomDigits(3)}-${_randomDigits(3)}-${_randomDigits(4)}';
    else if (country == GeneratorCountry.spain) phone += '${_random.nextInt(3) + 6}${_randomDigits(8)}';
    else if (country == GeneratorCountry.mexico) phone += '${_randomDigits(2)} ${_randomDigits(4)} ${_randomDigits(4)}';
    else phone += '7${_randomDigits(9)}';

    final birthYear = DateTime.now().year - (_random.nextInt(47) + 18);
    final dob = '$birthYear-${_pad(_random.nextInt(12) + 1)}-${_pad(_random.nextInt(28) + 1)}';

    final streetNumber = _random.nextInt(999) + 1;
    final address = country == GeneratorCountry.usa || country == GeneratorCountry.uk 
        ? '$streetNumber ${_getRandom(data['streets'])} ${_getRandom(data['streetTypes'])}'
        : '${_getRandom(data['streetTypes'])} ${_getRandom(data['streets'])} $streetNumber';

    return {
      'fullName': fullName,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'dateOfBirth': dob,
      'address': address,
      'city': _getRandom(data['cities']),
      'state': _getRandom(data['states']),
      'zipCode': _applyZipFormat(data['zipFormat']),
      'country': data['countryName'],
    };
  }

  static Map<String, String> generateCreditCard() {
    final cardTypes = ['VISA', 'MASTERCARD', 'AMEX', 'DISCOVER'];
    final cardType = _getRandom(cardTypes);
    String cardNumber = cardType == 'VISA' ? '4' : (cardType == 'MASTERCARD' ? '5' : (cardType == 'AMEX' ? '37' : '6011'));
    cardNumber += _randomDigits(cardType == 'AMEX' ? 13 : (cardType == 'DISCOVER' ? 12 : 15));

    return {
      'cardNumber': _formatCardNumber(cardNumber),
      'cardHolder': 'CYBER_USER_${_randomDigits(4)}',
      'expiration': '${_pad(_random.nextInt(12) + 1)}/${DateTime.now().year + _random.nextInt(5) - 2000 + 1}',
      'cvv': cardType == 'AMEX' ? _randomDigits(4) : _randomDigits(3),
      'cardType': cardType,
    };
  }

  static Map<String, String> generateLicense({GeneratorCountry country = GeneratorCountry.usa}) {
    final data = _localizedData[country]!;
    String licenseNumber;
    String authority;

    if (country == GeneratorCountry.spain) {
      final dniNumbers = _randomDigits(8);
      licenseNumber = '$dniNumbers${_calculateDNILetter(dniNumbers)}';
      authority = 'Dirección General de Tráfico';
    } else {
      licenseNumber = '${_randomLetter()}${_randomLetter()}${_randomDigits(7)}';
      authority = country == GeneratorCountry.usa ? '${_getRandom(data['states'])} DMV' : 'Driver & Vehicle Agency';
    }

    return {
      'documentNumber': licenseNumber,
      'issuingAuthority': authority,
      'issueDate': '${DateTime.now().year - _random.nextInt(5)}-${_pad(_random.nextInt(12)+1)}-${_pad(_random.nextInt(28)+1)}',
      'expiryDate': '${DateTime.now().year + _random.nextInt(5) + 2}-${_pad(_random.nextInt(12)+1)}-${_pad(_random.nextInt(28)+1)}',
    };
  }

  static Map<String, String> generatePassport({GeneratorCountry country = GeneratorCountry.usa}) {
    final data = _localizedData[country]!;
    String passportNumber = country == GeneratorCountry.spain 
        ? '${_randomLetter()}${_randomLetter()}${_randomDigits(6)}'.toUpperCase()
        : _randomDigits(9);
    
    return {
      'documentNumber': passportNumber,
      'issuingAuthority': country == GeneratorCountry.spain ? 'Ministerio del Interior' : 'Department of State',
      'issueDate': '${DateTime.now().year - 2}-${_pad(_random.nextInt(12)+1)}-${_pad(_random.nextInt(28)+1)}',
      'expiryDate': '${DateTime.now().year + 8}-${_pad(_random.nextInt(12)+1)}-${_pad(_random.nextInt(28)+1)}',
    };
  }

  static String generateUsername() {
    final names = _localizedData[GeneratorCountry.usa]!['firstNames'];
    final last = _localizedData[GeneratorCountry.usa]!['lastNames'];
    return '${_getRandom(names)}${_getRandom(last)}${_random.nextInt(99)}'.toLowerCase();
  }

  static String _getRandom(List<String> list) => list[_random.nextInt(list.length)];
  
  static String _randomDigits(int length) => List.generate(length, (_) => _random.nextInt(10)).join();

  static String _randomLetter() => String.fromCharCode(_random.nextInt(26) + 65);

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String _applyZipFormat(String format) {
    return format.replaceAllMapped('#', (_) => _random.nextInt(10).toString())
                 .replaceAllMapped('?', (_) => _randomLetter());
  }

  static String _formatCardNumber(String n) {
    return n.replaceAllMapped(RegExp(r".{4}"), (m) => "${m.group(0)} ").trim();
  }

  static String _calculateDNILetter(String numbers) {
    const letters = "TRWAGMYFPDXBNJZSQVHLCKE";
    return letters[int.parse(numbers) % 23];
  }
}
