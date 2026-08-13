import { WidgetCard } from "./WidgetCard";

type Props = {
  totalActivos: number;
  columnas: 1 | 2;
};

export function WidgetUsuarios({ totalActivos, columnas }: Props) {
  return (
    <WidgetCard titulo="Usuarios" icono="usuarios" href="/usuarios" columnas={columnas}>
      <p className="font-display font-bold text-h2 text-text-primary">{totalActivos}</p>
      <p className="t-caption mt-1">Usuarios activos</p>
    </WidgetCard>
  );
}
