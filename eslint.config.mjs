import js from '@eslint/js';
import vue from 'eslint-plugin-vue';

export default [
  {
    ignores: [
      'blueprints/**',
      'vendor/**',
      'config/**',
      '**/config/**',
      'server/**',
      'dist/**',
      'tmp/**',
      'node_modules/**',
      'coverage/**',
      '.node_modules.ember-try/**',
      'bower.json.ember-try',
      'package.json.ember-try',
    ],
  },
  js.configs.recommended,
  ...vue.configs['flat/recommended'],
  {
    files: ['src/**/*.{js,vue}'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: {
        document: 'readonly',
        fetch: 'readonly',
        navigator: 'readonly',
        window: 'readonly',
      },
    },
    rules: {
      'vue/multi-word-component-names': 'off',
      'vue/max-attributes-per-line': 'off',
      'vue/singleline-html-element-content-newline': 'off',
      'vue/html-self-closing': 'off',
    },
  },
];
