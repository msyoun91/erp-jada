import { WidgetCard } from "./WidgetCard";

type Props = {
  totalActivos: number;
  columnas: 1 | 2;
};

export function WidgetUsuarios({ totalActivos, columnas }: Props) {
  return (
    <WidgetCard titulo="Usuarios" icono="usuarios" href="/usuarios" columnas={columnas}>
      <p className="t-h2 tabular-nums">{totalActivos}</p>
      <p className="t-caption mt-1">Usuarios activos</p>
    </WidgetCard>
  );
}
