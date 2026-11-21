import { createPinia } from 'pinia'
import { createApp } from 'vue'

import App from './App.vue'
import { router } from './router'
import './styles/index.css'
import './styles/glass-prototype.css'
import { applyLookPrototype } from './styles/glass-prototype'

applyLookPrototype()

const app = createApp(App)

app.use(createPinia())
app.use(router)

app.mount('#app')
