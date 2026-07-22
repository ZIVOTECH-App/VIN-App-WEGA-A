const DURATION = 40 * 60 * 1000;
const WARNING = 5 * 60 * 1000;
const MAX_ACTIVE = 50;
const VIN_RE = /^[A-HJ-NPR-Z0-9]{17}$/;
let vehicles = JSON.parse(localStorage.getItem('vinVehicles') || '[]');
let history = JSON.parse(localStorage.getItem('vinHistory') || '[]');
let notified = new Set(JSON.parse(localStorage.getItem('vinNotified') || '[]'));
let stream = null, scanLoop = null;
const $ = id => document.getElementById(id);

function save(){localStorage.setItem('vinVehicles',JSON.stringify(vehicles));localStorage.setItem('vinHistory',JSON.stringify(history));localStorage.setItem('vinNotified',JSON.stringify([...notified]));}
function normalizeVin(v){return v.toUpperCase().replace(/[^A-Z0-9]/g,'').replace(/[IOQ]/g,'');}
function statusOf(v){const left=v.dueAt-Date.now();return left<=0?'expired':left<=WARNING?'soon':'active';}
function fmt(ms){if(ms<=0)return 'CZAS MINĄŁ';const s=Math.ceil(ms/1000),m=Math.floor(s/60),r=s%60;return `${String(m).padStart(2,'0')}:${String(r).padStart(2,'0')}`;}
function esc(s=''){return s.replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));}
function beep(){try{const a=new AudioContext(),o=a.createOscillator(),g=a.createGain();o.connect(g);g.connect(a.destination);o.frequency.value=880;g.gain.value=.12;o.start();setTimeout(()=>{o.stop();a.close()},500)}catch{}}
function notify(title,body,id){if(notified.has(id))return;notified.add(id);save();beep();if(Notification.permission==='granted')new Notification(title,{body,tag:id,requireInteraction:true});}
function checkAlerts(){for(const v of vehicles){const left=v.dueAt-Date.now();if(left<=0)notify('Czas pojazdu zakończony',`VIN ${v.vin} — upłynęło 40 minut.`,`expired-${v.id}`);else if(left<=WARNING)notify('Pozostało 5 minut',`VIN ${v.vin} zbliża się do końca czasu.`,`warning-${v.id}`);}}
function render(){
  const q=$('search').value.trim().toUpperCase(),f=$('filter').value;
  const sorted=[...vehicles].sort((a,b)=>a.dueAt-b.dueAt);
  const visible=sorted.filter(v=>(!q||v.vin.includes(q)||(v.location||'').toUpperCase().includes(q))&&(f==='all'||statusOf(v)===f));
  $('vehicleList').innerHTML=visible.length?visible.map(v=>{const st=statusOf(v);return `<article class="card ${st}"><div class="card-row"><div><div class="vin">${esc(v.vin)}</div><div class="meta">Start: ${new Date(v.startedAt).toLocaleString('pl-PL')} · Koniec: ${new Date(v.dueAt).toLocaleTimeString('pl-PL',{hour:'2-digit',minute:'2-digit'})}<br>${v.location?`Miejsce: ${esc(v.location)} · `:''}${v.operator?`Operator: ${esc(v.operator)}`:''}${v.note?`<br>Notatka: ${esc(v.note)}`:''}</div></div><div class="timer">${fmt(v.dueAt-Date.now())}</div></div><div class="card-actions"><button onclick="extendVehicle('${v.id}',5)">+5 min</button><button onclick="extendVehicle('${v.id}',10)">+10 min</button><button onclick="extendVehicle('${v.id}',20)">+20 min</button><button onclick="extendVehicle('${v.id}',40)">+40 min</button><button class="success" onclick="finishVehicle('${v.id}')">Zakończ</button><button class="danger" onclick="removeVehicle('${v.id}')">Usuń</button></div></article>`}).join(''):'<div class="empty">Brak pojazdów dla wybranego filtra.</div>';
  $('historyList').innerHTML=history.length?[...history].reverse().slice(0,100).map(v=>`<article class="card"><div class="vin">${esc(v.vin)}</div><div class="meta">${new Date(v.startedAt).toLocaleString('pl-PL')} → ${new Date(v.finishedAt).toLocaleString('pl-PL')}${v.location?` · ${esc(v.location)}`:''}</div></article>`).join(''):'<div class="empty">Historia jest pusta.</div>';
  $('activeCount').textContent=vehicles.filter(v=>statusOf(v)==='active').length;$('soonCount').textContent=vehicles.filter(v=>statusOf(v)==='soon').length;$('expiredCount').textContent=vehicles.filter(v=>statusOf(v)==='expired').length;
}
window.extendVehicle=(id,min)=>{const v=vehicles.find(x=>x.id===id);if(!v)return;v.dueAt=Math.max(v.dueAt,Date.now())+min*60000;notified.delete(`warning-${id}`);notified.delete(`expired-${id}`);save();render();};
window.finishVehicle=id=>{const i=vehicles.findIndex(x=>x.id===id);if(i<0)return;const [v]=vehicles.splice(i,1);history.push({...v,finishedAt:Date.now(),result:'completed'});save();render();};
window.removeVehicle=id=>{if(!confirm('Usunąć pojazd z aktywnej listy?'))return;const i=vehicles.findIndex(x=>x.id===id);if(i<0)return;const [v]=vehicles.splice(i,1);history.push({...v,finishedAt:Date.now(),result:'removed'});save();render();};

$('vin').addEventListener('input',e=>e.target.value=normalizeVin(e.target.value));
$('addForm').addEventListener('submit',e=>{e.preventDefault();const vin=normalizeVin($('vin').value),msg=$('formMessage');if(!VIN_RE.test(vin)){msg.textContent='VIN musi mieć 17 znaków i nie może zawierać I, O ani Q.';return}if(vehicles.some(v=>v.vin===vin)){msg.textContent='Ten VIN jest już na aktywnej liście.';return}if(vehicles.length>=MAX_ACTIVE){msg.textContent='Osiągnięto limit 50 aktywnych pojazdów.';return}const now=Date.now();vehicles.push({id:crypto.randomUUID(),vin,location:$('location').value.trim(),operator:$('operator').value.trim(),note:$('note').value.trim(),startedAt:now,dueAt:now+DURATION});save();e.target.reset();msg.textContent='Pojazd dodany. Uruchomiono 40 minut.';render();});
$('search').addEventListener('input',render);$('filter').addEventListener('change',render);
$('notifyBtn').onclick=async()=>{if(!('Notification'in window)){alert('Ta przeglądarka nie obsługuje powiadomień.');return}const p=await Notification.requestPermission();$('notifyBtn').textContent=p==='granted'?'Powiadomienia aktywne':'Powiadomienia wyłączone';};
$('exportBtn').onclick=()=>{const rows=[['VIN','Start','Koniec','Miejsce','Operator','Notatka','Status'],...history.map(v=>[v.vin,new Date(v.startedAt).toISOString(),new Date(v.finishedAt).toISOString(),v.location||'',v.operator||'',v.note||'',v.result])];const csv=rows.map(r=>r.map(x=>`"${String(x).replace(/"/g,'""')}"`).join(';')).join('\n');const a=document.createElement('a');a.href=URL.createObjectURL(new Blob(['\ufeff'+csv],{type:'text/csv'}));a.download=`vin-historia-${new Date().toISOString().slice(0,10)}.csv`;a.click();URL.revokeObjectURL(a.href);};

async function startScanner(){const d=$('scannerDialog');d.showModal();if(!('BarcodeDetector'in window)){ $('scanStatus').textContent='Ta przeglądarka nie obsługuje skanera kodów. Wpisz VIN ręcznie lub użyj Chrome na Androidzie.';return }try{const detector=new BarcodeDetector({formats:['code_128','code_39','qr_code','data_matrix']});stream=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'}}});$('video').srcObject=stream;await $('video').play();const loop=async()=>{if(!stream)return;try{const codes=await detector.detect($('video'));for(const c of codes){const vin=normalizeVin(c.rawValue||'');if(VIN_RE.test(vin)){$('vin').value=vin;stopScanner();$('formMessage').textContent='VIN odczytany ze skanera. Sprawdź i zatwierdź.';return}}}catch{}scanLoop=requestAnimationFrame(loop)};loop();}catch(e){$('scanStatus').textContent='Nie udało się uruchomić aparatu. Sprawdź uprawnienia.';}}
function stopScanner(){if(scanLoop)cancelAnimationFrame(scanLoop);scanLoop=null;if(stream)stream.getTracks().forEach(t=>t.stop());stream=null;if($('scannerDialog').open)$('scannerDialog').close();}
$('scanBtn').onclick=startScanner;$('scannerDialog').addEventListener('close',stopScanner);
if('serviceWorker'in navigator)navigator.serviceWorker.register('./sw.js');
render();checkAlerts();setInterval(()=>{render();checkAlerts()},1000);
