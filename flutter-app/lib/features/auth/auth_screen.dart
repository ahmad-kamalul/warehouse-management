import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../warehouse_controller.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.controller});
  final WarehouseController controller;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false, _obscure = true;
  String? _error;
  Map<String, String> _fields = {};
  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _fields = {};
    });
    if (!widget.controller.repository.isDemo &&
        !_form.currentState!.validate()) {
      return;
    }
    try {
      await widget.controller.authenticate(
        email: _email.text,
        password: _password.text,
        name: _register ? _name.text : null,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : 'Unable to sign in. Please retry.';
        _fields = e is ApiException ? e.fields : {};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.controller.authenticating;
    final demo = widget.controller.repository.isDemo;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: teal,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(
                            Icons.warehouse_outlined,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'WAREHOUSE / MOBILE',
                        style: TextStyle(
                          color: teal,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _register
                            ? 'Your inventory.\nOne place.'
                            : 'Everything in\nits place.',
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          height: 1.12,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _register
                            ? 'Create an account to start managing your stock.'
                            : 'Sign in to keep your warehouse moving.',
                        style: const TextStyle(
                          color: Color(0xFF61716F),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (demo)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Notice(
                            'Demo workspace · Sample inventory only. Changes reset when you sign out or restart.',
                          ),
                        ),
                      if (widget.controller.sessionMessage case final message?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Notice(message),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Notice(_error!, error: true),
                        ),
                      if (!demo) ...[
                        if (_register) ...[
                          TextFormField(
                            controller: _name,
                            enabled: !busy,
                            autofillHints: const [AutofillHints.name],
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: 'Full name',
                              errorText: _fields['name'],
                            ),
                            validator: (v) => Validators.requiredText(v, 100),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _email,
                          enabled: !busy,
                          autocorrect: false,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: InputDecoration(
                            labelText: 'Email address',
                            errorText: _fields['email'],
                          ),
                          validator: Validators.email,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          enabled: !busy,
                          obscureText: _obscure,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: [
                            _register
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          onFieldSubmitted: (_) {
                            if (!busy) _submit();
                          },
                          decoration: InputDecoration(
                            labelText: 'Password',
                            errorText: _fields['password'],
                            helperText: _register
                                ? 'At least 12 characters; up to 72 UTF-8 bytes.'
                                : null,
                            suffixIcon: IconButton(
                              tooltip: _obscure
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (v) =>
                              Validators.password(v, registration: _register),
                        ),
                        const SizedBox(height: 24),
                      ],
                      FilledButton(
                        onPressed: busy ? null : _submit,
                        child: busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                demo
                                    ? 'Explore demo workspace'
                                    : _register
                                    ? 'Create account'
                                    : 'Sign in',
                              ),
                      ),
                      if (!demo)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => setState(() {
                                  _register = !_register;
                                  _error = null;
                                  _fields = {};
                                  _password.clear();
                                  _form.currentState?.reset();
                                }),
                          child: Text(
                            _register
                                ? 'Already have an account? Sign in'
                                : 'New here? Create an account',
                          ),
                        ),
                      const SizedBox(height: 24),
                      const Text(
                        'Inventory clarity, wherever work takes you.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF61716F),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
