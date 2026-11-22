/* ② 매물장 — 테스트용 샘플 매물 50개 (id가 'SMP'로 시작, 한 번에 지우기 가능) */
(function(){
const B=window.__d1c;if(!B)return;
const {saveList,renderList,fallback,idbPut,idbDel,shrink,man,modal,toast,CH}=B;
const SID='SMP';
const pick=(a,r)=>a[Math.floor(r()*a.length)];
function rng(seed){let s=seed>>>0;return()=>{s=(s*1664525+1013904223)>>>0;return s/4294967296}}
const ROADS=[
 ['서울특별시 관악구 봉천동','관악로',['봉천역 도보 7분','서울대입구역 버스 5분']],
 ['서울특별시 관악구 신림동','신림로',['신림역 도보 5분','신림선 서원역 도보 3분']],
 ['서울특별시 관악구 남현동','남부순환로',['사당역 도보 8분','관악산 입구 가까움']],
 ['서울특별시 동작구 상도동','상도로',['장승배기역 도보 6분','숭실대 인근']],
 ['서울특별시 동작구 사당동','동작대로',['사당역 도보 4분','이수역 환승 편리']],
 ['서울특별시 금천구 독산동','시흥대로',['독산역 도보 9분','가산디지털단지 출퇴근 편리']],
 ['서울특별시 구로구 구로동','구로중앙로',['구로디지털단지역 도보 6분','구로시장 가까움']],
 ['서울특별시 영등포구 신길동','신길로',['신풍역 도보 5분','여의도 버스 15분']],
 ['서울특별시 중랑구 면목동','면목로',['면목역 도보 4분','중랑천 산책로 가까움']],
 ['서울특별시 중랑구 상봉동','망우로',['상봉역 도보 5분','코스트코·이마트 가까움']],
 ['경기도 광명시 철산동','철산로',['철산역 도보 6분','광명시청 인근']],
 ['경기도 안양시 만안구 안양동','만안로',['안양역 도보 8분','안양천 산책로']]];
const BLD=['그린빌','해오름','하늘채','스카이뷰','라온','미소','드림하우스','청솔','한빛','다온'];
const PLUS=['2024년 도배·장판 새로 함','남향이라 오후까지 밝음','집주인 같은 건물 거주로 관리 잘 됨','주변 편의점·카페 많음','층간소음 민원 이력 없음','수납공간 넉넉함','창문 크고 환기 잘 됨','골목 조용하고 가로등 밝음','반려동물 협의 가능','대형마트 도보 10분'];
const OPTS=['에어컨','냉장고','세탁기','가스레인지','인덕션','전자레인지','붙박이장','신발장','책상','침대','비데','도어락','CCTV'];
const DIRS=['남향','남동향','남서향','동향','서향','북향'];
const MONTHS=['12월','1월','2월','3월'];
// 종류별 규칙: [type, use, deal후보, 면적범위, 방, 층범위]
const KINDS=[
 ['원룸','다세대주택',['월세','월세','전세','단기임대'],[16,28],1,[2,5]],
 ['원룸','다가구주택',['월세','월세','전세'],[15,25],1,[1,4]],
 ['투룸','다세대주택',['월세','전세','전세','매매'],[30,45],2,[2,5]],
 ['쓰리룸+','다세대주택',['전세','매매','매매'],[48,72],3,[2,6]],
 ['오피스텔','오피스텔',['월세','월세','전세','매매'],[18,40],1,[3,18]],
 ['아파트','아파트',['전세','매매','매매','월세'],[49,114],3,[2,24]],
 ['빌라','연립주택',['전세','매매'],[45,80],3,[1,4]],
 ['단독·다가구','다가구주택',['매매'],[150,330],8,[0,0]],
 ['상가','제1종근린생활시설',['월세','월세','매매'],[25,120],0,[1,2]],
 ['사무실','업무시설',['월세','월세'],[33,165],0,[2,12]],
 ['토지','',['매매'],[200,1200],0,[0,0]]];
function price(kind,deal,area,r){
  const base={원룸:1,투룸:1.25,'쓰리룸+':1.5,오피스텔:1.1,아파트:3,빌라:1.4,'단독·다가구':4,상가:1.6,사무실:1.3,토지:1}[kind[0]];
  const rnd=(a,b,s)=>Math.round((a+(b-a)*r())/s)*s;
  if(kind[0]==='토지')return{price:Math.round(area*rnd(150,600,10)/100)*100};
  if(deal==='매매')return{price:kind[0]==='단독·다가구'?rnd(90000,260000,1000):Math.round(area*base*rnd(600,1300,10)/100)*100};
  if(deal==='전세')return{deposit:Math.round(area*base*rnd(300,700,10)/100)*100};
  if(deal==='단기임대')return{deposit:rnd(100,300,50),rent:rnd(70,110,5)};
  const dep=kind[0]==='상가'||kind[0]==='사무실'?rnd(1000,5000,500):rnd(300,2000,100);
  const rent=kind[0]==='상가'||kind[0]==='사무실'?Math.round(area*rnd(25,50,1)/10)*1:Math.round(area*base*rnd(15,24,1)/10);
  return{deposit:dep,rent:Math.max(35,rent)};
}
function iso(d){return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0')}
function shift(days){const d=new Date();d.setHours(0,0,0,0);d.setDate(d.getDate()+days);return iso(d)}
const PAL=[['#F77235','#FFE3D3'],['#23292B','#DDE3E5'],['#2F7D5B','#DCF1E6'],['#3E6FB0','#DCE8F7'],['#9A5BB5','#EFE1F6'],['#B8862E','#F6EBD3']];
function photo(i,k,label,sub){return new Promise(res=>{const c=document.createElement('canvas');c.width=960;c.height=720;const g=c.getContext('2d');
  const [a,b]=PAL[(i+k)%PAL.length];const gr=g.createLinearGradient(0,0,960,720);gr.addColorStop(0,b);gr.addColorStop(1,'#ffffff');g.fillStyle=gr;g.fillRect(0,0,960,720);
  g.fillStyle=a;g.globalAlpha=.18;for(let j=0;j<6;j++){g.fillRect(80+j*140,260-(j%3)*40,110,460)}g.globalAlpha=1;
  g.fillStyle=a;g.font='bold 64px sans-serif';g.textAlign='center';g.fillText(label,480,300);
  g.fillStyle='#23292B';g.font='36px sans-serif';g.fillText(sub,480,370);
  g.font='bold 28px sans-serif';g.fillStyle='#C9531B';g.fillText('샘플 사진 '+(k+1)+' — 테스트용',480,640);
  c.toBlob(b=>res(b),'image/jpeg',.8)})}
function thumbOf(blob){return new Promise(res=>{const r=new FileReader();r.onload=()=>res(r.result);r.onerror=()=>res(null);shrink(blob,160,.7).then(b=>r.readAsDataURL(b)).catch(()=>res(null))})}
const ROOMS=['거실','방','주방','욕실','외관'];

async function addSamples(n){
  const r=rng(20261122);const keep=B.D;const made=[];
  for(let i=0;i<n;i++){
    const kind=KINDS[i%KINDS.length],road=ROADS[(i*7)%ROADS.length],deal=pick(kind[2],r);
    const area=Math.round((kind[3][0]+(kind[3][1]-kind[3][0])*r())*100)/100;
    const land=kind[0]==='토지',det=kind[1]==='단독주택'||kind[1]==='다가구주택';
    const tf=land?'':det?String(3+Math.floor(r()*2)):String(Math.max(kind[5][1],3)+Math.floor(r()*3));
    const fl=land||det?'':String(kind[5][0]+Math.floor(r()*(Math.min(kind[5][1],+tf)-kind[5][0]+1)));
    const jibun=(100+Math.floor(r()*900))+'-'+(1+Math.floor(r()*40));
    const p=price(kind,deal,area,r);
    const mv=pick(['now','date','nego'],r);
    const opts=land||kind[0]==='상가'||kind[0]==='사무실'?[]:OPTS.filter(()=>r()<.45);
    const memo=[pick(road[2],r),pick(PLUS,r),pick(PLUS,r)].filter((x,j,a)=>a.indexOf(x)===j).join(', ');
    const dd={id:SID+String(i+1).padStart(2,'0'),type:kind[0],deal,use:kind[1],addr:road[0]+' '+jibun,
      bldgName:land||det?'':pick(BLD,r)+(kind[0]==='아파트'?'아파트':kind[0]==='오피스텔'?'오피스텔':'빌'),
      dong:kind[0]==='아파트'?(101+Math.floor(r()*8))+'동':'',dongNone:kind[0]!=='아파트',ho:land||det?'':(fl||'1')+'0'+(1+Math.floor(r()*4))+'호',
      floorMode:'exact',floor:fl,totalFloor:tf,baseFloor:det?'1':'',
      area:String(area),supply:kind[0]==='아파트'||kind[0]==='오피스텔'?String(Math.round(area*1.32*100)/100):'',
      rooms:kind[4]?String(kind[4]+(kind[0]==='아파트'&&area<60?-1:0)):'',baths:kind[4]?String(kind[4]>=3?2:1):'',
      dir:land?'':pick(DIRS,r),dirBase:'거실 기준',approve:land?'':(1992+Math.floor(r()*32))+'-'+String(1+Math.floor(r()*12)).padStart(2,'0')+'-15',
      elevator:land||det?'':(+tf>=5?'있음':'없음'),parkTotal:land?'':String(Math.floor(r()*(kind[0]==='아파트'?300:12))),
      moveMode:land?'':mv,moveDate:mv==='date'?shift(10+Math.floor(r()*50)):'',moveMonth:mv==='nego'?pick(MONTHS,r):'',movePart:mv==='nego'?pick(['초','중순','말'],r):'',
      mgmtType:land?'':'정액',mgmtTotal:land?'':String(kind[0]==='아파트'?Math.round(15+r()*20):Math.round(5+r()*10)),mgmtIncl:land?[]:['공용관리비','수도료','인터넷'].filter(()=>r()<.6),mgmtDetail:{},
      options:opts,memo,blockMode:{},price:p.price!=null?String(p.price):'',deposit:p.deposit!=null?String(p.deposit):'',rent:p.rent!=null?String(p.rent):'',sample:true};
    B.D=dd;let out=null;try{out=fallback(pick(['신뢰형','친근형','간결형'],r));Object.keys(CH).forEach(k=>{out[k]=out[k]||{title:'',body:''};out[k].blk=out[k].blk||CH[k].blk})}catch(e){out=null}
    const st=i<38?'광고중':i<46?'거래완료':'보류';
    let startOff=-Math.floor(r()*24);if(i%9===0)startOff=-28-Math.floor(r()*3);if(i%17===0)startOff=-32;const endOff=startOff+30;
    const label=[road[0].split(' ').pop(),kind[0],deal].join(' ');
    const sub=deal==='매매'?man(dd.price):man(dd.deposit)+(dd.rent?' / '+man(dd.rent):'');
    const blobs=[];for(let k=0;k<(land?2:4);k++)blobs.push(await photo(i,k,land?['토지 전경','진입로'][k]:label,land?road[0].split(' ').slice(1).join(' '):ROOMS[k]+' · '+sub));
    await idbPut(dd.id,blobs);
    made.push({id:dd.id,data:JSON.parse(JSON.stringify(dd)),outputs:out,adStart:shift(startOff),adEnd:shift(endOff),status:st,takenDown:st==='거래완료'?i%2===0:false,doneAt:st==='거래완료'?shift(-1-Math.floor(r()*10)):undefined,saved:new Date(Date.now()-i*36e5).toISOString(),thumb:await thumbOf(blobs[0]),sample:true});
  }
  B.D=keep;
  B.list=B.list.filter(x=>!String(x.id).startsWith(SID)).concat(made);saveList();renderList();
  try{localStorage.setItem('d1c.listings',JSON.stringify(B.list))}catch(e){toast('저장 공간이 부족해요');return}
  toast('샘플 매물 '+n+'개를 넣었어요');
}
async function clearSamples(){const s=B.list.filter(x=>String(x.id).startsWith(SID));for(const x of s)await idbDel(x.id);B.list=B.list.filter(x=>!String(x.id).startsWith(SID));saveList();renderList();toast('샘플 매물 '+s.length+'개를 지웠어요')}
function mount(){const box=document.getElementById('btnRestore');if(!box||document.getElementById('btnSample'))return;
  const a=document.createElement('button');a.className='btn sm';a.id='btnSample';a.textContent='🧪 샘플 매물 50개';
  const b=document.createElement('button');b.className='btn sm';b.id='btnSampleDel';b.textContent='샘플 지우기';
  box.after(a,b);
  a.onclick=()=>modal('샘플 매물 50개 넣기','<p>테스트용 가상 매물 50개(원룸~토지, 월세·전세·매매, 광고중·거래완료·보류, 만료 임박 포함)와 샘플 사진을 넣습니다.</p><p class="hint">내가 저장한 매물은 그대로 둡니다. "샘플 지우기"로 샘플만 한 번에 지울 수 있어요. ③ AI쇼츠·⑧ 블로그에서도 이 매물을 고를 수 있습니다.</p>',[{t:'취소'},{t:'넣기',cls:'pri',fn:()=>{toast('샘플 매물 만드는 중…');addSamples(50)}}]);
  b.onclick=()=>{const n=B.list.filter(x=>String(x.id).startsWith(SID)).length;if(!n){toast('지울 샘플이 없어요');return}modal('샘플 지우기','<p>샘플 매물 '+n+'개와 샘플 사진을 지웁니다. 내가 저장한 매물은 그대로입니다.</p>',[{t:'취소'},{t:'지우기',cls:'dark',fn:clearSamples}])};
}
mount();
window.__d1cSample={addSamples,clearSamples};
})();
