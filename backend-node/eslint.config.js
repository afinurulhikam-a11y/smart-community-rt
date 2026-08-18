const js = require("@eslint/js");
module.exports = [
  js.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "commonjs",
      globals: {
        require: "readonly",
        module: "readonly",
        process: "readonly",
        console: "readonly",
        Buffer: "readonly",
        setImmediate: "readonly",
        clearImmediate: "readonly",
        setTimeout: "readonly",
        clearTimeout: "readonly",
        setInterval: "readonly",
        clearInterval: "readonly",
        __dirname: "readonly",
        __filename: "readonly",
        fetch: "readonly"
      }
    },
    rules: {
      // Tiga pola "tak terpakai" di bawah ini semuanya disengaja:
      //   - ignoreRestSiblings: `const { password_hash, ...userData } = user`
      //     adalah cara membuang kolom sensitif dari respons, bukan variabel
      //     yang lupa dipakai.
      //   - argsIgnorePattern `next`: Express mengenali error handler dari
      //     jumlah argumennya, jadi `next` wajib ada meski tidak dipanggil.
      //   - caughtErrors none: `catch (err)` yang errornya sengaja diabaikan.
      "no-unused-vars": ["error", {
        ignoreRestSiblings: true,
        argsIgnorePattern: "^next$|^_",
        caughtErrors: "none"
      }]
    }
  }
];
