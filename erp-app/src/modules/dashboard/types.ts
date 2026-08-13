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
];

export type DashboardData = {
  totalUsuariosActivos: number;
};
