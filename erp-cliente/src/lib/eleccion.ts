const ALFABETO = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

export type VentanaElegida = { ancho: number; n: number };

// El formato lo fija sql/204_presupuestos_eleccion.sql: el ERP lo lee con la misma regla.
export function codigoEleccion(codigoPresupuesto: string, version: number, ventanas: VentanaElegida[]): string {
  const numero = Number(codigoPresupuesto.replace(/^P-/, ""));
  let bits = ventanas.filter((v) => v.ancho > 0).map((v) => v.n.toString(2).padStart(v.ancho, "0")).join("");
  bits = bits.padEnd(Math.ceil(bits.length / 5) * 5, "0");
  let letras = "";
  for (let i = 0; i < bits.length; i += 5) letras += ALFABETO[parseInt(bits.slice(i, i + 5), 2)];
  const base = `${numero}V${version}${letras}`;
  let suma = 0;
  for (let i = 0; i < base.length; i++) suma += ((i % 30) + 1) * ALFABETO.indexOf(base[i]);
  const resto = `${letras}${ALFABETO[suma % 31]}`.match(/.{1,4}/g)!.join("-");
  return `P-${numero.toString().padStart(4, "0")}-V${version}-${resto}`;
}
