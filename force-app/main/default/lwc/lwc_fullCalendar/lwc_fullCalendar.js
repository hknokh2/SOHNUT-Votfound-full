import { LightningElement,api,track  } from 'lwc';
import { loadStyle, loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import FullCalendarJS from '@salesforce/resourceUrl/FullCalendarJS';
import getVisits from '@salesforce/apex/Lwc_fullCalendar.getVisits';
import { NavigationMixin } from 'lightning/navigation';

export default class Lwc_fullCalendar extends NavigationMixin(LightningElement) 
{
    jsInitialised = false;
    @track _visits = [];

    /*[
      {
        title: "Interview - Location A",
        start: "2023-10-24T08:00:00",
        end: "2023-10-24T10:00:00",       
      },
      {
        title: "Interview - Location B",
        start: "2023-10-25T09:30:00",
        end: "2023-10-25T11:30:00",       
      },
      {
        title: "Interview - Location C",
        start: "2023-10-26T14:00:00",
        end: "2023-10-26T16:00:00",       
      }
    ];*/
  

    @api
    get visits() {
        return this._visits;
    }
    set visits(value) {
        this._visits=[...value];
    }


    /*@api
    get eventDataString() {
        return this.visits;
    }
    set eventDataString(value) {
        try
        {
            this.visits=eval(value);
        }
        catch{
           this.visits=[];
        }
    }*/

  async renderedCallback() {

    // Performs this operation only on first render
    if (this.jsInitialised) {
      return;
    }
    else
    {
    this.jsInitialised = true;

    Promise.all([  
      loadScript(this, FullCalendarJS + '/jquery.min.js'),
      loadScript(this, FullCalendarJS + '/moment.min.js'),     
      loadScript(this, FullCalendarJS + '/fullcalendar.min.js'),     
      loadStyle(this, FullCalendarJS + '/fullcalendar.min.css'),
    ])
    .then(() => {
       // Initialise the calendar configuration       
        setTimeout(()=> {
          console.log('delay');
          this.initialiseCalendarJs();
        },3000)    
    })
    .catch(error => {
        //alert(error);
        console.log(error);        
    })
   }
  }

  async initialiseCalendarJs() { 

    //Get visits from Visit__c object
    try
    {
      let result = await getVisits({});
      console.log(result);
      if(result)
      {
        var visits =[];
        result.forEach(item => {
          const event = {
            title: item.Name ,
            start: item.Start_Date__c,
            end: item.End_Date__c ,
            visitId: item.Id,
            contactId: item.Contact__c,
            mitkan: item.Mitkan__c          
          };
    
          // Push the event object to the visits array
          visits.push(event);
        });

        this._visits = visits;
        console.log(this._visits);
        
      }
    } 
    catch(error)
    {
      console.log(error);
    }    

    const ele = this.template.querySelector('div.fullcalendarjs');
    //Use jQuery to instantiate fullcalender JS
    $(ele).fullCalendar({
      header: {
          left: 'prev,next today',
          center: 'title',
          right: 'month,basicWeek,basicDay'
      },
      defaultDate: new Date(),
      navLinks: true, 
      editable: false,
      eventLimit: true,
      events: this.visits,
      /*dragScroll:true,
      droppable:true,
      weekNumbers:true,
      selectable:true,*/
      timezone: 'local',
      displayEventEnd:true,
      timeFormat: "HH:mm" ,      
      /*eventClick:(info)=> {
        console.log(info);

        //Navigate to record page
        this[NavigationMixin.GenerateUrl]({
          type: "standard__recordPage",
          attributes: {
              recordId: info.visitId,
              objectApiName: 'Visit__c',
              actionName: 'view'
          }
      }).then(url => {
          window.open(url, "_blank");
      });

      },*/   
       eventRender: function(event, element) {
       
        
        //element.style.pointerEvents = 'none';
       
        element.find(".fc-title").on("click", function(e) {
          e.preventDefault();
          window.open("/"+event.visitId, "_blank");
        });

        //element.find(".fc-title").style.pointerEvents = 'all';

        if(event.contactId)
        {
          element.find(".fc-title").append('<br><span class="contact-icon" title="contact">👤</span>');
          element.find(".contact-icon").on("click", function(e) {
            e.preventDefault();
            window.open("/"+event.contactId, "_blank");
          }); 
          //element.find("contact-icon").style.pointerEvents = 'all';
        }

        
        if(event.mitkan)
        {
          element.find(".fc-title").append('<span class="mitkan-icon" title="Mitkan">🏢</span>');
          element.find(".mitkan-icon").on("click", function(e) {
            e.preventDefault();
            window.open("/"+event.mitkan, "_blank");
          })
         //element.find(".mitkan-icon").style.pointerEvents = 'all';
        }

    },
    });
  }
}