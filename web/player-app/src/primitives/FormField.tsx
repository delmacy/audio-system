export type FormPrimitiveColor = 'blue' | 'gray' | 'red' | 'green' | 'purple'
export type FormPrimitiveMotion = 'static' | 'pulse'

function formClass(base: string, color: FormPrimitiveColor, motion: FormPrimitiveMotion, disabled: boolean) {
  return [
    base,
    `form-primitive-${color}`,
    `form-primitive-motion-${motion}`,
    disabled ? 'form-primitive-disabled' : '',
  ].filter(Boolean).join(' ')
}

export function Field({
  color = 'blue',
  motion = 'static',
  label = 'Field',
  helper,
  disabled = false,
  placeholder = 'Digite um valor',
  type = 'text',
  defaultValue,
}: {
  color?: FormPrimitiveColor
  motion?: FormPrimitiveMotion
  label?: string
  helper?: string
  disabled?: boolean
  placeholder?: string
  type?: 'text' | 'password' | 'email' | 'number' | 'search'
  defaultValue?: string
}) {
  return <label className={formClass('form-primitive-field', color, motion, disabled)}>
    <span>{label}</span>
    <input type={type} disabled={disabled} placeholder={placeholder} defaultValue={defaultValue} />
    {helper && <small>{helper}</small>}
  </label>
}

export function TextareaField({
  color = 'blue',
  motion = 'static',
  label = 'Textarea',
  helper,
  disabled = false,
  placeholder = 'Digite o conteúdo',
  rows = 4,
  defaultValue,
}: {
  color?: FormPrimitiveColor
  motion?: FormPrimitiveMotion
  label?: string
  helper?: string
  disabled?: boolean
  placeholder?: string
  rows?: number
  defaultValue?: string
}) {
  return <label className={formClass('form-primitive-field form-primitive-textarea', color, motion, disabled)}>
    <span>{label}</span>
    <textarea disabled={disabled} placeholder={placeholder} rows={rows} defaultValue={defaultValue} />
    {helper && <small>{helper}</small>}
  </label>
}

export const FORM_PRIMITIVE_COLORS: FormPrimitiveColor[] = ['blue', 'gray', 'red', 'green', 'purple']
