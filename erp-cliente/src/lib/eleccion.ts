import type { Combinacion, Renglon } from "./tipos";

// La combinación ofrecida más parecida a tocar `clave`: respeta lo tocado y cambia lo menos posible del resto; en empate, la de
// menos casillas. Solo elige entre las que trae la copia: nunca arma una que no se ofrece. Null si ninguna respeta lo tocado.
export function cercana(r: Pick<Renglon, "combinaciones">, actual: string[], clave: string): Combinacion | null {
  const quiere = !actual.includes(clave);
  const deseadas = quiere ? [...actual, clave] : actual.filter((c) => c !== clave);
  let mejor: Combinacion | null = null;
  let costo = Infinity;
  for (const c of r.combinaciones) {
    if (c.casillas.includes(clave) !== quiere) continue;
    const distintas = c.casillas.filter((x) => !deseadas.includes(x)).length + deseadas.filter((x) => !c.casillas.includes(x)).length;
    const k = distintas * 1000 + c.casillas.length;
    if (k < costo) [mejor, costo] = [c, k];
  }
  return mejor;
}

const ALFABETO ="0123456789ABCDEFGHJKMNPQRSTVWXYZ";

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
