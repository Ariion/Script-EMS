const { ModuleFederationPlugin } = require('webpack').container;
const path = require('path');

module.exports = {
  mode: 'production',
  entry: './src/index.ts',
  output: {
    path: path.resolve(__dirname, 'dist'),
    filename: 'bundle.js',
    publicPath: 'https://agenda/npwd_app/dist/',
    clean: true,
  },
  resolve: {
    extensions: ['.tsx', '.ts', '.js'],
  },
  module: {
    rules: [
      {
        test: /\.tsx?$/,
        use: {
          loader: 'ts-loader',
          options: { transpileOnly: true },
        },
        exclude: /node_modules/,
      },
    ],
  },
  plugins: [
    new ModuleFederationPlugin({
      name: 'agenda',
      filename: 'remoteEntry.js',
      exposes: {
        './config': './src/config',
      },
      shared: {
        react: {
          singleton: true,
          requiredVersion: false,
          eager: false,
        },
        'react-dom': {
          singleton: true,
          requiredVersion: false,
          eager: false,
        },
        'react-router-dom': {
          singleton: true,
          requiredVersion: false,
          eager: false,
        },
      },
    }),
  ],
};
