export type WidgetDefinicion = {
  id: string;
  titulo: string;
  columnas: 1 | 2;
  moduloRequerido: string;
  icono: string;
};

export const WIDGETS: WidgetDefinicion[] = [
  {
    id: "usuarios",
    titulo: "Usuarios",
    columnas: 1,
    moduloRequerido: "usuarios",
    icono: "usuarios",
  },
  // Lo dibuja Obras; `app/(erp-app)/page.tsx` lo compone (`modulos`).
  {
    id: "obras",
    titulo: "Obras",
    columnas: 2,
    moduloRequerido: "obras",
    icono: "obras",
  },
];

export type DashboardData = {
  totalUsuariosActivos: number;
};
