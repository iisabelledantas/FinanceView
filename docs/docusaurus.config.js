// @ts-check
// `@type` JSDoc annotations allow editor autocompletion and type checking
// (when paired with `@ts-check`).
// There are various equivalent ways to declare your Docusaurus config.
// See: https://docusaurus.io/docs/api/docusaurus-config

import {themes as prismThemes} from 'prism-react-renderer';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'FinanceView',
  tagline: 'Documentação técnica da plataforma de finanças pessoais',
  favicon: 'img/financeview-icon-192.png',

  // Future flags, see https://docusaurus.io/docs/api/docusaurus-config#future
  future: {
    v4: true, // Improve compatibility with the upcoming Docusaurus v4
  },

  // Set the production url of your site here
  url: 'https://financeview.local',
  // Set the /<baseUrl>/ pathname under which your site is served
  // For GitHub pages deployment, it is often '/<projectName>/'
  baseUrl: '/',

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
  organizationName: 'financeview',
  projectName: 'financeview-docs',

  onBrokenLinks: 'throw',

  // Even if you don't use internationalization, you can use this field to set
  // useful metadata like html lang. For example, if your site is Chinese, you
  // may want to replace "en" with "zh-Hans".
  i18n: {
    defaultLocale: 'pt-BR',
    locales: ['pt-BR'],
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          sidebarPath: './sidebars.js',
          routeBasePath: '/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      image: 'img/financeview-icon-192.png',
      colorMode: {
        defaultMode: 'dark',
        respectPrefersColorScheme: true,
      },
      navbar: {
        title: 'FinanceView',
        logo: {
          alt: 'FinanceView',
          src: 'img/financeview-icon-192.png',
        },
        items: [
          {
            type: 'docSidebar',
            sidebarId: 'financeviewSidebar',
            position: 'left',
            label: 'Documentação',
          },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Docs',
            items: [
              {
                label: 'Introdução',
                to: '/',
              },
              {
                label: 'Arquitetura',
                to: '/architecture',
              },
              {
                label: 'Backend',
                to: '/backend',
              },
              {
                label: 'Frontend',
                to: '/frontend',
              },
            ],
          },
          {
            title: 'Projeto',
            items: [
              {
                label: 'Banco de Dados',
                to: '/database',
              },
              {
                label: 'Infraestrutura',
                to: '/infrastructure',
              },
              {
                label: 'Serviços',
                to: '/services',
              },
            ],
          },
        ],
        copyright: `Copyright © ${new Date().getFullYear()} FinanceView. Documentação técnica do projeto.`,
      },
      prism: {
        theme: prismThemes.github,
        darkTheme: prismThemes.dracula,
      },
    }),
};

export default config;
