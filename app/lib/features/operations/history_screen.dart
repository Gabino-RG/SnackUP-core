import 'package:flutter/material.dart';
import '../../operations/models.dart';
import '../../operations/operations_repository.dart';
import '../../operations/kitchen_controller.dart';
import '../admin/admin_theme.dart';

class HistoryScreen extends StatefulWidget{
  const HistoryScreen({super.key,required this.repository,required this.businessId,this.summaryOnly=false});
  final OperationsRepository repository;
  final String businessId;
  final bool summaryOnly;
  @override
  State<HistoryScreen> createState()=>_HistoryScreenState();
}
class _HistoryScreenState extends State<HistoryScreen>{
  DateTime _day=campusNow(),_from=campusNow().subtract(const Duration(days:6));
  OrderHistory? _history;
  SalesSummary? _summary;
  bool _busy=true;
  String? _error;
  int _page=1,_revision=0;
  @override
  void initState(){super.initState();_load();}
  Future<void> _load()async{
    final revision=++_revision;setState((){_busy=true;_error=null;});
    try{
      if(widget.summaryOnly){final summary=await widget.repository.stats(widget.businessId,dayKey(_from),dayKey(_day));if(mounted&&revision==_revision)setState(()=>_summary=summary);}
      else{final history=await widget.repository.history(widget.businessId,dayKey(_day),number:_page);if(mounted&&revision==_revision)setState((){_history=history;_summary=history.summary;});}
    }catch(e){if(mounted&&revision==_revision)setState(()=>_error=operationsMessage(e));}
    finally{if(mounted&&revision==_revision)setState(()=>_busy=false);}
  }
  Future<void> _pick(bool start)async{
    final chosen=await showDatePicker(context:context,initialDate:start?_from:_day,firstDate:DateTime(2020),lastDate:DateTime(campusNow().year,campusNow().month,campusNow().day));
    if(chosen!=null&&mounted){setState((){if(start){_from=chosen;if(_from.isAfter(_day))_day=_from;}else{_day=chosen;if(_day.isBefore(_from))_from=_day;}_page=1;});_load();}
  }
  @override
  Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(20),children:[
    Text(widget.summaryOnly?'Resumen de ventas':'Historial de pedidos',style:Theme.of(context).textTheme.headlineLarge),
    const SizedBox(height:8),const Text('Fechas del campus · America/Mexico_City · Importes en MXN'),const SizedBox(height:18),
    Wrap(spacing:12,runSpacing:10,children:[if(widget.summaryOnly)OutlinedButton.icon(onPressed:_busy?null:()=>_pick(true),icon:const Icon(Icons.date_range),label:Text('Desde ${dayKey(_from)}')),
      OutlinedButton.icon(onPressed:_busy?null:()=>_pick(false),icon:const Icon(Icons.calendar_today),label:Text('${widget.summaryOnly?'Hasta':'Día'} ${dayKey(_day)}')),
      IconButton(tooltip:'Actualizar',onPressed:_busy?null:_load,icon:const Icon(Icons.refresh))]),
    const SizedBox(height:20),
    if(_busy)const Center(child:CircularProgressIndicator())
    else if(_error!=null)Column(children:[Text(_error!),TextButton(onPressed:_load,child:const Text('Reintentar'))])
    else if(_summary!=null)...[
      Wrap(spacing:16,runSpacing:16,children:[_metric('Ventas entregadas',money(_summary!.totalCents),Icons.payments_outlined),_metric('Pedidos entregados','${_summary!.completed}',Icons.check_circle_outline),_metric('Cancelaciones','${_summary!.cancelled}',Icons.cancel_outlined)]),
      const Padding(padding:EdgeInsets.symmetric(vertical:16),child:Text('Los importes y conteos corresponden al periodo completo informado por el servidor. Los pedidos cancelados no se incluyen en las ventas.')),
      if(!widget.summaryOnly&&_history!=null)...[
        if(_history!.orders.items.isEmpty)const Padding(padding:EdgeInsets.all(32),child:Text('No hay pedidos finalizados en esta fecha.')),
        for(final o in _history!.orders.items)Card(child:ExpansionTile(title:Text('#${o.number} · ${o.customer}'),subtitle:Text('${o.status.label} · ${money(o.totalCents)}'),children:[
          Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            Text('Creado: ${campusStamp(o.createdAt)}'),Text('Pago: ${o.payment}'),
            for(final item in o.items)Text('${item.quantity} × ${item.name}${item.notes.isEmpty?'':' · ${item.notes}'}'),
            if(o.cancelReason!=null)Text('Motivo: ${cancelReasons[o.cancelReason]??o.cancelReason}'),
            if(o.cancelNotes?.isNotEmpty??false)Text(o.cancelNotes!),
          ]))])),
        Row(mainAxisAlignment:MainAxisAlignment.center,children:[IconButton(tooltip:'Página anterior',onPressed:_page>1?(){_page--;_load();}:null,icon:const Icon(Icons.chevron_left)),
          Text('Página $_page de ${_history!.orders.totalPages.clamp(1,99999)}'),IconButton(tooltip:'Página siguiente',onPressed:_history!.orders.hasMore?(){_page++;_load();}:null,icon:const Icon(Icons.chevron_right))]),
      ],
    ],
  ]);
  Widget _metric(String label,String value,IconData icon)=>SizedBox(width:240,child:Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:AdminColors.cyan),const SizedBox(height:16),Text(value,style:const TextStyle(fontSize:28,fontWeight:FontWeight.w800,color:AdminColors.navy)),Text(label)]))));
}
